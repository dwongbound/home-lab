// The page in jsdom with fetch faked: the blocking spinner on first load,
// the overview, the error state, the Unload Gemma flow and Ask Jarvis.
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
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
function fakeServer(options: { actionGate?: Promise<void> } = {}) {
  const source = createMockSource()
  return vi.fn(async (url: string, init?: RequestInit) => {
    if (url === '/api/snapshot') return Response.json(await source.snapshot())
    if (url.startsWith('/api/actions/') && init?.method === 'POST') {
      if (options.actionGate) await options.actionGate
      return Response.json(await source.action(url.split('/').pop()))
    }
    if (url === '/api/home/control' && init?.method === 'POST') {
      const { entity, command, value } = JSON.parse(String(init.body))
      return Response.json(await source.control(entity, command, value))
    }
    if (url === '/api/jarvis/ask' && init?.method === 'POST') {
      return Response.json(await source.ask(JSON.parse(String(init.body)).text))
    }
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
    // The overview is a glance: no chart, services list or Gemma card.
    expect(screen.getByRole('heading', { name: 'Today' })).toBeInTheDocument()
    expect(screen.queryByRole('heading', { name: 'Jarvis requests' })).not.toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Unload Gemma' })).not.toBeInTheDocument()
    // Jarvis needs attention, the 9 am run failed, and two threads wait on him.
    expect(screen.getByRole('link', { name: '4 things need you.' })).toHaveAttribute('href', '#claude')
  })

  it('explains how to fix it when the server is unreachable', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => new Response('', { status: 502 })))
    renderApp()
    expect(await screen.findByRole('alert')).toHaveTextContent('Can’t reach the jarvis server')
    expect(screen.getByRole('button', { name: 'Try again' })).toBeInTheDocument()
  })

  it('unloads Gemma: confirm dialog with Close, blocking spinner while it runs, then a toast', async () => {
    let release!: () => void
    const gate = new Promise<void>((resolve) => { release = resolve })
    vi.stubGlobal('fetch', fakeServer({ actionGate: gate }))
    const user = userEvent.setup()
    // The Gemma card lives on Services.
    window.location.hash = '#services'
    renderApp()

    await user.click(await screen.findByRole('button', { name: 'Unload Gemma' }))
    const dialog = screen.getByRole('dialog', { hidden: true })
    expect(dialog).toHaveTextContent('Unload Gemma?')
    expect(screen.getByRole('button', { name: 'Close', hidden: true })).toBeEnabled()

    await user.click(screen.getByRole('button', { name: 'Unload', hidden: true }))
    expect(await screen.findByText('Unloading Gemma…')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Close', hidden: true })).toBeDisabled()

    release()
    expect(await screen.findByText('Gemma unloaded', {}, { timeout: 3000 })).toBeInTheDocument()
    await waitFor(() => expect(screen.getByRole('button', { name: 'Load Gemma' })).toBeInTheDocument())
  })

  it('Close dismisses the dialog without doing anything', async () => {
    const fetch = fakeServer()
    vi.stubGlobal('fetch', fetch)
    const user = userEvent.setup()
    window.location.hash = '#services'
    renderApp()
    await user.click(await screen.findByRole('button', { name: 'Unload Gemma' }))
    await user.click(screen.getByRole('button', { name: 'Close', hidden: true }))
    expect(screen.queryByRole('dialog', { hidden: true })).not.toBeInTheDocument()
    expect(fetch.mock.calls.some((c) => String(c[0]).startsWith('/api/actions/'))).toBe(false)
  })

  it('asks Jarvis and shows the question and the answer', async () => {
    const fetch = fakeServer()
    vi.stubGlobal('fetch', fetch)
    const user = userEvent.setup()
    renderApp()

    const input = await screen.findByRole('textbox', { name: 'Question for Jarvis' })
    expect(screen.getByRole('button', { name: 'Ask' })).toBeDisabled()
    await user.type(input, 'Is the porch light on?')
    await user.click(screen.getByRole('button', { name: 'Ask' }))

    expect(await screen.findByText('Sample data: on the PC, Jarvis would answer "Is the porch light on?" here.', {}, { timeout: 3000 })).toBeInTheDocument()
    expect(screen.getByText('Is the porch light on?')).toBeInTheDocument()
    expect(input).toHaveValue('')
    const [, init] = fetch.mock.calls.find((c) => c[0] === '/api/jarvis/ask')!
    expect((init!.headers as Record<string, string>)['x-home-lab']).toBe('1')
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
