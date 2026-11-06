// The API, as a plain Node request handler:
//
//   GET  /api/snapshot              everything the page shows, in one call
//   POST /api/actions/ollama-unload free Gemma's ~10 GB of GPU memory
//   POST /api/actions/ollama-load   load Gemma back (about 3 minutes)
//
// The production server (server/index.mjs) and the Vite dev server
// (vite.config.ts) both mount this same handler, so dev and prod can't drift.
import { createMockSource } from './sources/mock.mjs'
import { createLiveSource } from './sources/live.mjs'

const ACTIONS = new Set(['ollama-unload', 'ollama-load'])
const ACTION_PATH = /^\/api\/actions\/([a-z-]+)$/

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

/**
 * Builds the request handler around a data source. Requests outside /api/
 * go to `next` (the static file server), or 404 when there's no `next`.
 */
export function createApi(source) {
  // Only one action at a time: loading Gemma twice at once would just
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
      return sendJson(res, 404, { error: 'Not found' })
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err)
      return sendJson(res, 500, { error: message })
    }
  }
}
