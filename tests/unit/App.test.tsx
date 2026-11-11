// The page in jsdom with fetch faked: the blocking spinner on first load,
// the overview, the error state, the unload-the-local-model flow and Ask Jarvis.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fireEvent, render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { SWRConfig } from 'swr'
import { App } from '../../src/App'
import { createMockSource } from '../../server/sources/mock.mjs'

/** Renders the app with a fresh SWR cache so tests don't share data. */
function renderApp() {
  return render(
    <SWRConfig value={{ provider: () => new Map(), dedupingInterval: 0 }}>
      <App />
    </SWRConfig>,
  )
}

/** Answers /api/* from a real mock source, the way the server would. */
function fakeServer(options: { actionGate?: Promise<void>; live?: boolean } = {}) {
  const source = createMockSource()
  return vi.fn(async (url: string, init?: RequestInit) => {
    if (url === '/api/snapshot') {
      // live: pretend the snapshot came from the PC, so Talk opens the real voice line.
      const snap = await source.snapshot()
      return Response.json(options.live ? { ...snap, source: 'live' } : snap)
    }
    if (url.startsWith('/api/actions/') && init?.method === 'POST') {
      if (options.actionGate) await options.actionGate
      return Response.json(await source.action(url.split('/').pop()))
    }
    if (url === '/api/home/control' && init?.method === 'POST') {
      const { entity, command, value } = JSON.parse(String(init.body))
      return Response.json(await source.control(entity, command, value))
    }
    if (url === '/api/jarvis/chat' && init?.method === 'POST') {
      // Streamed like the real server: one JSON event per line as Jarvis writes.
      const text = JSON.parse(String(init.body)).text
      const body = new ReadableStream({
        async start(controller) {
          await source.chat(text, {}, (event: unknown) => controller.enqueue(new TextEncoder().encode(`${JSON.stringify(event)}\n`)))
          controller.close()
        },
      })
      return new Response(body, { headers: { 'content-type': 'application/x-ndjson' } })
    }
    if (url === '/api/jarvis/history') return Response.json({ turns: await source.history() })
    if (url === '/api/jarvis/voice' && init?.method === 'POST') return Response.json(await source.setVoice(JSON.parse(String(init.body))))
    if (url === '/api/jarvis/voice') return Response.json({ voice: await source.voice() })
    if (url.startsWith('/api/jarvis/voice/sample?')) return new Response(new Uint8Array([82, 73, 70, 70]), { headers: { 'content-type': 'audio/wav' } })
    if (url === '/api/jarvis/memory' && init?.method === 'POST') return Response.json(await source.changeMemory(JSON.parse(String(init.body))))
    if (url === '/api/jarvis/memory') return Response.json({ memory: await source.memory() })
    if (url.startsWith('/api/jarvis/memory/search?q=')) return Response.json({ hits: await source.searchMemory(decodeURIComponent(url.split('q=')[1])) })
    return new Response('not found', { status: 404 })
  })
}

beforeEach(() => {
  window.location.hash = ''
})
afterEach(() => {
  vi.unstubAllGlobals()
})

describe('App', () => {
  it('shows a blocking spinner until the first snapshot arrives, then the overview', async () => {
    vi.stubGlobal('fetch', fakeServer())
    renderApp()
    expect(screen.getByRole('status')).toHaveTextContent('Jarvis is thinking')
    expect(await screen.findByRole('heading', { level: 1 })).toHaveTextContent(/, Dylan$/)
    expect(screen.getByText('Sample data')).toBeInTheDocument()
    // The overview is a glance: no chart, services list or model card.
    expect(screen.getByRole('heading', { name: 'Today' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Jarvis requests' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Unload local model' })).not.toBeInTheDocument()
    // Jarvis needs attention, the 9 am run failed, and two threads wait on him.
    expect(screen.getByRole('link', { name: '4 things need you.' })).toHaveAttribute('href', '#claude')
  })

  it('explains how to fix it when the server is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('', { status: 502 })))
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('Can’t reach the jarvis server')
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument()
  })

  it('unloads the local model: confirm dialog with Close, blocking spinner while it runs, then a toast', async () => {
    let release!: () => void
    const gate = new Promise<void>((resolve) => { release = resolve })
    vi.stubGlobal('fetch', fakeServer({ actionGate: gate }))
    const user = userEvent.setup()
    // The model card lives on Services.
    window.location.hash = '#services'
    renderApp()

    await user.click(await screen.findByRole('button', { name: 'Unload local model' }))
    const dialog = screen.getByRole('dialog', { hidden: true })
    expect(dialog).toHaveTextContent('Unload the local model?')
    expect(screen.getByRole('button', { name: 'Close', hidden: true })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Unload', hidden: true }))
    expect(await screen.findByText('Unloading the local model…')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Close', hidden: true })).toBeDisabled()

    release()
    expect(await screen.findByText('Local model unloaded', {}, { timeout: 3000 })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Load local model' })).toBeInTheDocument())
  })

  it('Close dismisses the dialog without doing anything', async () => {
    const fetch = fakeServer()
    vi.stubGlobal('fetch', fetch)
    const user = userEvent.setup()
    window.location.hash = '#services'
    renderApp()
    await user.click(await screen.findByRole('button', { name: 'Unload local model' }))
    await user.click(screen.getByRole('button', { name: 'Close', hidden: true }))
    expect(screen.queryByRole('dialog', { hidden: true })).not.toBeInTheDocument()
    expect(fetch.mock.calls.some((c) => String(c[0]).startsWith('/api/actions/'))).toBe(false)
  })

  it('asks Jarvis from the bar, opens the chat, and types out the answer', async () => {
    const fetch = fakeServer()
    vi.stubGlobal('fetch', fetch)
    const user = userEvent.setup()
    renderApp()

    const input = await screen.findByRole('textbox', { name: 'Question for Jarvis' })
    // An empty box offers Talk; typing swaps it for Ask.
    expect(screen.queryByRole('button', { name: 'Ask' })).not.toBeInTheDocument()
    await user.type(input, 'Is the garage open?')
    await user.click(screen.getByRole('button', { name: 'Ask' }))

    // The chat opens with the question in it and the reply typed out.
    const chat = await screen.findByRole('dialog', { name: 'Jarvis' })
    expect(within(chat).getByText('Is the garage open?')).toBeInTheDocument()
    expect(await within(chat).findByText('Sample data: on the PC, Jarvis would answer "Is the garage open?" here.', {}, { timeout: 4000 })).toBeInTheDocument()
    expect(await within(chat).findByText('Type below, or tap Talk')).toBeInTheDocument()
    const [, init] = fetch.mock.calls.find((c) => c[0] === '/api/jarvis/chat')!
    expect((init!.headers as Record<string, string>)['x-home-lab']).toBe('1')

    // Close keeps the conversation: the bar shows the last reply and reopens it.
    await user.click(within(chat).getByRole('button', { name: 'Close' }))
    expect(screen.queryByRole('dialog', { name: 'Jarvis' })).not.toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: /Open chat/ }))
    expect(within(await screen.findByRole('dialog', { name: 'Jarvis' })).getByText('Is the garage open?')).toBeInTheDocument()
  })

  it('Talk with sample data plays the demo turn hands-free until Stop talking', async () => {
    vi.stubGlobal('fetch', fakeServer())
    const user = userEvent.setup()
    renderApp()

    await user.click(await screen.findByRole('button', { name: 'Talk' }))
    const chat = await screen.findByRole('dialog', { name: 'Jarvis' })
    expect(within(chat).getByRole('status')).toHaveTextContent('Listening… just talk')
    // The first demo question is "heard", asked, and answered.
    expect(await within(chat).findByText(/you have volleyball at 7:30/, {}, { timeout: 8000 })).toBeInTheDocument()
    await user.click(within(chat).getByRole('button', { name: 'Stop talking' }))
    expect(await within(chat).findByRole('button', { name: 'Talk' }, { timeout: 4000 })).toBeInTheDocument()
  }, 15_000)

  it("Talk with live data opens the voice line, and says why when it can't", async () => {
    // jsdom has no microphone, so the line refuses and the chat says so.
    vi.stubGlobal('fetch', fakeServer({ live: true }))
    const user = userEvent.setup()
    renderApp()

    await user.click(await screen.findByRole('button', { name: 'Talk' }))
    const chat = await screen.findByRole('dialog', { name: 'Jarvis' })
    expect(await within(chat).findByRole('status')).toHaveTextContent('This browser can’t send your voice to Jarvis')
    expect(within(chat).getByRole('button', { name: 'Talk' })).toBeEnabled()
    expect(within(chat).queryByRole('button', { name: 'Stop talking' })).not.toBeInTheDocument()
  })

  it('Settings: what Jarvis remembers, forgetting one after a confirm, adding one, and searching', async () => {
    vi.stubGlobal('fetch', fakeServer())
    window.location.hash = '#preferences'
    const user = userEvent.setup()
    renderApp()

    const panel = await screen.findByRole('region', { name: 'Memory' })
    const facts = await within(panel).findByRole('list', { name: 'Things Jarvis remembers' })
    expect(within(facts).getByText('Wants weather in °F and wind in knots.')).toBeInTheDocument()

    await user.click(within(panel).getByRole('button', { name: 'Forget: Wants weather in °F and wind in knots.' }))
    const confirm = await screen.findByRole('dialog', { hidden: true })
    expect(confirm).toHaveTextContent('Forget this?')
    await user.click(within(confirm).getByRole('button', { name: 'Forget', hidden: true }))
    await waitFor(() => expect(within(panel).queryByText('Wants weather in °F and wind in knots.')).not.toBeInTheDocument())

    await user.type(within(panel).getByRole('textbox', { name: 'Something for Jarvis to remember' }), 'Likes oat milk')
    await user.click(within(panel).getByRole('button', { name: 'Remember' }))
    expect(await within(panel).findByText('Likes oat milk')).toBeInTheDocument()

    await user.type(within(panel).getByRole('searchbox', { name: 'Search past conversations' }), 'volleyball')
    await user.click(within(panel).getByRole('button', { name: 'Search' }))
    const results = await within(panel).findByRole('list', { name: 'Search results' })
    expect(within(results).getByText(/check the weather before volleyball/)).toBeInTheDocument()
  })

  it('Settings: picking a voice, the speed and a blend, playing a sample, and saving', async () => {
    const fetch = fakeServer()
    vi.stubGlobal('fetch', fetch)
    window.location.hash = '#preferences'
    const user = userEvent.setup()
    renderApp()

    const panel = await screen.findByRole('region', { name: 'Voice' })
    const voices = await within(panel).findByRole('list', { name: 'Voices' })
    expect(within(voices).getByRole('radio', { name: /George/ })).toBeChecked()
    expect(within(panel).getByRole('button', { name: 'Save' })).toBeDisabled()

    await user.click(within(panel).getByRole('button', { name: 'Play Lewis' }))
    await waitFor(() => expect(fetch.mock.calls.some((c) => String(c[0]).startsWith('/api/jarvis/voice/sample?voice=bm_lewis'))).toBe(true))

    await user.click(within(panel).getByRole('radio', { name: 'American' }))
    await user.click(within(panel).getByRole('radio', { name: /Heart/ }))
    fireEvent.change(within(panel).getByRole('slider', { name: /Speed/ }), { target: { value: '110' } })
    expect(within(panel).getByText('1.10×')).toBeInTheDocument()
    await user.click(within(panel).getByRole('switch', { name: 'Blend in a second voice' }))
    expect(within(panel).getByText(/70% Heart · 30% /)).toBeInTheDocument()

    await user.click(within(panel).getByRole('button', { name: 'Save' }))
    await waitFor(() => expect(within(panel).getByRole('status')).toHaveTextContent(/^Saved/))
    const saved = fetch.mock.calls.find((c) => c[0] === '/api/jarvis/voice' && c[1]?.method === 'POST')
    expect(JSON.parse(String(saved?.[1]?.body))).toMatchObject({ voice: 'af_heart', speed: 1.1, blend: { mix: 0.3 } })
  })

  it('Home: turning a switch on, and a scene with no on/off', async () => {
    vi.stubGlobal('fetch', fakeServer())
    window.location.hash = '#home'
    const user = userEvent.setup()
    renderApp()

    const porch = await screen.findByRole('region', { name: 'Porch lights' })
    expect(porch).toHaveTextContent('Off')
    await user.click(within(porch).getByRole('button', { name: 'Turn on' }))
    await waitFor(() => expect(within(porch).getByRole('button', { name: 'Turn off' })).toHaveAttribute('aria-pressed', 'true'))
    expect(screen.getByRole('region', { name: 'TV' })).toHaveTextContent('Unavailable')
    expect(within(screen.getByRole('region', { name: 'Movie night' })).getByRole('button', { name: 'Run' })).toBeEnabled()
  })

  it('switches pages from the hash', async () => {
    vi.stubGlobal('fetch', fakeServer())
    window.location.hash = '#services'
    renderApp()
    expect(await screen.findByRole('heading', { level: 1, name: 'Services' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Services' })).toHaveAttribute('aria-current', 'page')
  })
})
