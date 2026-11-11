// Hands-free Talk on the Overview: a WebSocket proxy from /api/jarvis/talk
// to Jarvis's own voice pipeline (/talk/ws?chat=web on its local API), so
// spoken turns land in the same web chat as typed ones.
//
// Jarvis checks the Tailscale-User-Login header itself; `tailscale serve`
// sets that header on every request, replacing anything a browser sent.
// This proxy adds two locks of its own: there must be a login at all, and
// the WebSocket must come from this page (its Origin), so another website
// open in Dylan's browser can't open his microphone line to Jarvis.
import net from 'node:net'

export const TALK_PATH = '/api/jarvis/talk'

/** True for the Talk WebSocket's path (any query string is ignored). */
export function isTalkPath(url) {
  const { pathname } = new URL(url ?? '/', 'http://localhost')
  return pathname === TALK_PATH
}

/** Whether this upgrade may reach Jarvis. Returns null when it may, or the HTTP status to refuse with. */
export function talkRefusal(req) {
  const login = String(req.headers['tailscale-user-login'] ?? '')
  if (!login) return 403
  const origin = req.headers.origin
  const host = req.headers.host ?? ''
  if (!origin || (origin !== `https://${host}` && origin !== `http://${host}`)) return 403
  return null
}

/**
 * Creates the proxy's upgrade handler. Node hands over the raw socket, so
 * the upgrade request is replayed to Jarvis with its path rewritten, and
 * the two sockets are then joined.
 */
export function createTalkProxy(config) {
  const target = new URL(config.jarvisApiUrl)
  const port = Number(target.port || 80)

  /** Proxies one Talk WebSocket, or refuses it. */
  function upgrade(req, socket, head) {
    const refusal = talkRefusal(req)
    if (refusal !== null) {
      socket.end(`HTTP/1.1 ${refusal} Refused\r\nConnection: close\r\n\r\n`)
      return
    }
    const upstream = net.connect(port, target.hostname, () => {
      let raw = `GET /talk/ws?chat=web HTTP/1.1\r\n`
      for (let i = 0; i < req.rawHeaders.length; i += 2) {
        const name = req.rawHeaders[i]
        // Jarvis is addressed directly, so its own host goes in Host.
        if (name.toLowerCase() === 'host') raw += `Host: ${target.host}\r\n`
        else raw += `${name}: ${req.rawHeaders[i + 1]}\r\n`
      }
      upstream.write(`${raw}\r\n`)
      if (head && head.length > 0) upstream.write(head)
      upstream.pipe(socket)
      socket.pipe(upstream)
    })
    // Either side closing ends the other, so no half-open sockets linger.
    upstream.on('error', () => socket.destroy())
    socket.on('error', () => upstream.destroy())
  }

  return { upgrade }
}
