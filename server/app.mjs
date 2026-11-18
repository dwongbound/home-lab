// The API, as a plain Node request handler:
//
//   GET  /api/snapshot              everything the page shows, in one call
//   POST /api/actions/ollama-unload free the local model's ~6 GB of GPU memory
//   POST /api/actions/ollama-load   load it back
//   POST /api/jarvis/ask            {"text": "..."} -> Jarvis's reply
//   POST /api/jarvis/chat           {"text": "..."} -> Jarvis's reply, streamed as NDJSON
//   GET  /api/jarvis/history        the web chat so far
//   GET  /api/jarvis/memory         what Jarvis remembers ({memory})
//   GET  /api/jarvis/memory/search?q=  past conversations matching q ({hits})
//   POST /api/jarvis/memory         {"op": "remember", "text"} | {"op": "forget", "id"}
//   GET  /api/jarvis/voice          how Jarvis sounds + every voice; POST saves {voice, speed, blend}
//   GET  /api/jarvis/voice/sample   a WAV of ?voice=&speed=&voice2=&mix=
//   POST /api/jarvis/approve        {"id", "ok"} -> Approve or Deny one thing Jarvis asked to do on the PC
//   GET  /api/jarvis/approvals      what Jarvis is still waiting on you to approve ({pending})
//   POST /api/jarvis/offers/hide   {"id"} -> Hide on one of Jarvis's offer cards
//   POST /api/jarvis/notices/clear {"ids"} or {"all": true} -> clears notifications on every device
//   POST /api/jarvis/push/register {"token", "platform", "environment", "bundle"} -> an app asking for pushes
//   POST /api/jarvis/feedback      {question, answer, note} -> "That was wrong" on one of his replies
//   POST /api/jarvis/sleep          {"asleep": true|false, "source"?} -> tells Jarvis you've gone to bed, or are up
//   POST /api/jarvis/warm           starts Jarvis's web-chat engine early (the chat sheet opened)
//   POST /api/home/control          {"entity", "command", "value"?} -> one Home Assistant device
//   POST /api/digest/refresh        -> asks Jarvis to rewrite the digest; {running, lastWrite}
//   POST /api/money/picks           {"op": "pick" | "clear" | "remind", ...} -> Money page category picks
//
// The production server (server/index.mjs) and the Vite dev server
// (vite.config.ts) both mount this same handler, so dev and prod can't drift.
import { createMockSource } from './sources/mock.mjs'
import { createLiveSource } from './sources/live.mjs'
import { checkVoiceChoice, choiceFromQuery } from './voice.mjs'
import { parseClear, parsePushDevice } from './sources/notices.mjs'

const ACTIONS = new Set(['ollama-unload', 'ollama-load'])
const ACTION_PATH = /^\/api\/actions\/([a-z-]+)$/
const MAX_BODY_BYTES = 8 * 1024

/** Picks the data source from config: "live" reads the PC, anything else is mock. */
export function createSource(config) {
  if (config.dataSource === 'live') return createLiveSource(config)
  return createMockSource()
}

/** Writes a JSON response that browsers and proxies won't cache. */
function sendJson(res, status, body) {
  res.statusCode = status
  res.setHeader('content-type', 'application/json')
  res.setHeader('cache-control', 'no-store')
  res.end(JSON.stringify(body))
}

/** Reads a small JSON request body, or null when it's missing, too big or not JSON. */
async function readJson(req) {
  let raw = ''
  for await (const chunk of req) {
    raw += chunk
    if (raw.length > MAX_BODY_BYTES) return null
  }
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

/**
 * Builds the request handler around a data source. Requests outside /api/
 * go to `next` (the static file server), or 404 when there's no `next`.
 */
export function createApi(source) {
  // Only one action at a time: loading the model twice at once would just
  // fight over the same GPU memory.
  let actionInFlight = null

  /** Runs one action, refusing if another is still going. */
  async function handleAction(req, res, name) {
    if (!ACTIONS.has(name)) {
      return sendJson(res, 404, { ok: false, message: `Unknown action: ${name}` })
    }
    // A cross-site form post can't set a custom header, so this stops
    // another web page from triggering actions on the PC.
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    if (actionInFlight !== null) {
      return sendJson(res, 409, { ok: false, message: `Still working on ${actionInFlight}` })
    }

    actionInFlight = name
    try {
      const result = await source.action(name)
      return sendJson(res, result.ok ? 200 : 502, result)
    } finally {
      actionInFlight = null
    }
  }

  /**
   * Passes a question to Jarvis. Jarvis decides who may ask: the server
   * forwards the Tailscale-User-Login header that `tailscale serve` adds,
   * and Jarvis checks it against its own allow list, so the page holds no
   * Jarvis password.
   */
  async function handleAsk(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    const text = typeof body?.text === 'string' ? body.text.trim() : ''
    if (!text) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"text": "..."}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.ask(text, { login })
    return sendJson(res, result.ok ? 200 : 502, result)
  }

  /**
   * Chats with Jarvis, streaming his reply back as it's written: one JSON
   * event per line (application/x-ndjson), ending with done or error.
   */
  async function handleChat(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    const text = typeof body?.text === 'string' ? body.text.trim() : ''
    if (!text) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"text": "..."}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    // Start on an offer card: Jarvis marks it started and takes it as Dylan's ask.
    const caller = { login }
    if (typeof body.offerId === 'string' && /^[\w-]{1,64}$/.test(body.offerId)) caller.offerId = body.offerId
    res.writeHead(200, { 'content-type': 'application/x-ndjson; charset=utf-8', 'cache-control': 'no-store' })
    // If the phone leaves mid-reply, keep reading Jarvis's answer to the end
    // (he saves it to the chat history) and just stop writing to the page.
    await source.chat(text, caller, (event) => {
      if (!res.destroyed && !res.writableEnded) res.write(`${JSON.stringify(event)}\n`)
    })
    res.end()
  }

  /** The web chat so far, so the page can show it after a reload. */
  async function handleHistory(req, res) {
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { turns: await source.history({ login }) })
  }

  /** What Jarvis remembers. */
  async function handleMemory(req, res) {
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { memory: await source.memory({ login }) })
  }

  /** Searches Jarvis's past conversations. */
  async function handleMemorySearch(req, res, query) {
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { hits: await source.searchMemory(query, { login }) })
  }

  /** Adds or forgets one fact. */
  async function handleMemoryChange(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    const remember = body?.op === 'remember' && typeof body.text === 'string' && body.text.trim() !== ''
    const forget = body?.op === 'forget' && typeof body.id === 'string'
    if (!remember && !forget) {
      return sendJson(res, 400, { ok: false, message: 'Send {"op": "remember", "text": "..."} or {"op": "forget", "id": "..."}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    let change = { op: 'forget', id: body.id }
    if (remember) change = { op: 'remember', text: body.text.trim().slice(0, 500) }
    const result = await source.changeMemory(change, { login })
    return sendJson(res, result.ok ? 200 : 502, result)
  }

  /** How Jarvis sounds, and the voices he has. */
  async function handleVoice(req, res) {
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { voice: await source.voice({ login }) })
  }

  /** Saves how Jarvis sounds. */
  async function handleVoiceChange(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const checked = checkVoiceChoice(await readJson(req))
    if (checked.error) return sendJson(res, 400, { ok: false, message: checked.error })
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.setVoice(checked.choice, { login })
    return sendJson(res, result.ok ? 200 : 502, result)
  }

  /** A spoken sample of one voice choice, as WAV. */
  async function handleVoiceSample(req, res, params) {
    const checked = choiceFromQuery(params)
    if (checked.error) return sendJson(res, 400, { ok: false, message: checked.error })
    const login = req.headers['tailscale-user-login'] ?? ''
    const sample = await source.voiceSample(checked.choice, { login })
    if (!sample.ok) return sendJson(res, 502, sample)
    res.writeHead(200, { 'content-type': 'audio/wav', 'content-length': sample.audio.byteLength, 'cache-control': 'private, max-age=3600' })
    res.end(Buffer.from(sample.audio.buffer, sample.audio.byteOffset, sample.audio.byteLength))
  }

  /** Gets Jarvis's web-chat engine started before the first question, so it answers sooner. */
  async function handleWarm(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { ok: await source.warm({ login }) })
  }

  /** Approves or denies one thing Jarvis asked to do (write a file, run a command). */
  async function handleApprove(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    if (typeof body?.id !== 'string' || body.id.length > 64 || typeof body.ok !== 'boolean') {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"id": "a1", "ok": true}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.answerApproval(body.id, body.ok, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** Hide on an offer card: Jarvis drops it and won't offer it again soon. */
  async function handleHideOffer(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    if (typeof body?.id !== 'string' || !/^[\w-]{1,64}$/.test(body.id)) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"id": "o1"}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.hideOffer(body.id, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** Clear on a notification (or Clear all): Jarvis drops it, so it goes from every device. */
  async function handleClearNotices(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const which = parseClear(await readJson(req))
    if (which === null) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"ids": ["n1"]} or {"all": true}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.clearNotices(which, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** An app's push token, passed to Jarvis so he can send lock-screen notifications to that device. */
  async function handleRegisterPush(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const device = parsePushDevice(await readJson(req))
    if (device === null) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"token": "ab12…", "platform": "ios", "environment": "production", "bundle": "com.example.app"}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.registerPush(device, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** Night mode on a screen (the Apple TV): tells Jarvis you've gone to bed, or that you're up again. */
  async function handleSleep(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    if (typeof body?.asleep !== 'boolean') {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"asleep": true}' })
    }
    // Where it came from is only a label for Jarvis's log; anything odd becomes "page".
    let from = 'page'
    if (typeof body.source === 'string' && /^[a-z]{1,16}$/.test(body.source)) from = body.source
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.setSleep(body.asleep, from, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** "That was wrong" on one of his replies: Jarvis saves it and works it into a fix and a test overnight. */
  async function handleFeedback(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const flag = feedbackFrom(await readJson(req))
    if (flag === null) {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"question": "…", "answer": "…", "note": "…"}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.sendFeedback(flag, { login })
    return sendJson(res, result.ok ? 200 : 409, result)
  }

  /** What Jarvis is still waiting on an answer for (after a reload, say). */
  async function handleApprovals(req, res) {
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { pending: await source.approvals({ login }) })
  }

  /** Sends one command to one Home Assistant device (server/sources/home.mjs). */
  async function handleControl(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    if (typeof body?.entity !== 'string' || typeof body?.command !== 'string') {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"entity": "light.lamp", "command": "toggle"}' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    const result = await source.control(body.entity, body.command, body.value, { login })
    return sendJson(res, result.ok ? 200 : 502, result)
  }

  /** Asks Jarvis to rewrite the digest, as whoever opened the page. */
  async function handleDigestRefresh(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, await source.refreshDigest({ login }))
  }

  /**
   * Saves, clears or re-times a category picked on the Money page. Copilot
   * is read-only, so these wait on the PC until Dylan applies them there.
   */
  async function handleMoneyPicks(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const body = await readJson(req)
    if (body === null || typeof body !== 'object') {
      return sendJson(res, 400, { ok: false, message: 'Send JSON like {"op": "pick", "id": "...", "category": "..."}' })
    }
    const result = await source.money(body)
    return sendJson(res, result.ok ? 200 : 400, result)
  }

  return async function api(req, res, next) {
    const { pathname } = new URL(req.url ?? '/', 'http://localhost')
    if (!pathname.startsWith('/api/')) {
      if (next) return next()
      return sendJson(res, 404, { error: 'Not found' })
    }

    try {
      if (req.method === 'GET' && pathname === '/api/snapshot') {
        return sendJson(res, 200, await source.snapshot())
      }
      const actionMatch = pathname.match(ACTION_PATH)
      if (req.method === 'POST' && actionMatch) {
        return await handleAction(req, res, actionMatch[1])
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/ask') {
        return await handleAsk(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/chat') {
        return await handleChat(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/history') {
        return await handleHistory(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/memory') {
        return await handleMemory(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/memory/search') {
        const query = new URL(req.url ?? '/', 'http://localhost').searchParams.get('q') ?? ''
        return await handleMemorySearch(req, res, query.slice(0, 200))
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/memory') {
        return await handleMemoryChange(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/voice') {
        return await handleVoice(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/voice') {
        return await handleVoiceChange(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/voice/sample') {
        return await handleVoiceSample(req, res, new URL(req.url ?? '/', 'http://localhost').searchParams)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/approve') {
        return await handleApprove(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/offers/hide') {
        return await handleHideOffer(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/notices/clear') {
        return await handleClearNotices(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/push/register') {
        return await handleRegisterPush(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/sleep') {
        return await handleSleep(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/feedback') {
        return await handleFeedback(req, res)
      }
      if (req.method === 'GET' && pathname === '/api/jarvis/approvals') {
        return await handleApprovals(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/jarvis/warm') {
        return await handleWarm(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/home/control') {
        return await handleControl(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/digest/refresh') {
        return await handleDigestRefresh(req, res)
      }
      if (req.method === 'POST' && pathname === '/api/money/picks') {
        return await handleMoneyPicks(req, res)
      }
      return sendJson(res, 404, { error: 'Not found' })
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      return sendJson(res, 500, { error: message })
    }
  }
}

// The longest question, answer and note a flag may carry (characters).
const FEEDBACK_TEXT_MAX = 8000
const FEEDBACK_NOTE_MAX = 2000

/**
 * Checks a "That was wrong" body and returns {question, answer, note}, or
 * null when it isn't one: the answer is required, the rest may be empty.
 */
export function feedbackFrom(body) {
  if (body === null || typeof body !== 'object') return null
  const { question = '', answer, note = '' } = body
  if (typeof question !== 'string' || typeof answer !== 'string' || typeof note !== 'string') return null
  if (!answer.trim()) return null
  if (question.length > FEEDBACK_TEXT_MAX || answer.length > FEEDBACK_TEXT_MAX || note.length > FEEDBACK_NOTE_MAX) return null
  return { question: question.trim(), answer: answer.trim(), note: note.trim() }
}
