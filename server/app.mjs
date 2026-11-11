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
//   POST /api/jarvis/warm           starts Jarvis's web-chat engine early (the chat sheet opened)
//   POST /api/home/control          {"entity", "command", "value"?} -> one Home Assistant device
//   POST /api/digest/refresh        -> asks Jarvis to rewrite the digest; {running, lastWrite}
//   POST /api/money/picks           {"op": "pick" | "clear" | "remind", ...} -> Money page category picks
//
// The production server (server/index.mjs) and the Vite dev server
// (vite.config.ts) both mount this same handler, so dev and prod can't drift.
import { createMockSource } from './sources/mock.mjs'
import { createLiveSource } from './sources/live.mjs'

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
    res.writeHead(200, { 'content-type': 'application/x-ndjson; charset=utf-8', 'cache-control': 'no-store' })
    await source.chat(text, { login }, (event) => res.write(`${JSON.stringify(event)}\n`))
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

  /** Gets Jarvis's web-chat engine started before the first question, so it answers sooner. */
  async function handleWarm(req, res) {
    if (req.headers['x-home-lab'] !== '1') {
      return sendJson(res, 403, { ok: false, message: 'Missing x-home-lab header' })
    }
    const login = req.headers['tailscale-user-login'] ?? ''
    return sendJson(res, 200, { ok: await source.warm({ login }) })
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
