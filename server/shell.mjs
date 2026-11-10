// The Shell page's terminal: a reverse proxy from /shell/ to ttyd, which
// runs tmux on this PC and listens on 127.0.0.1 only (deploy/ttyd.service).
//
// ttyd has no login of its own, so this is the lock on the door. A request
// gets through only when all three hold:
//   1. SHELL_USERS is set (empty means the shell is off),
//   2. the Tailscale-User-Login header that `tailscale serve` adds is one of
//      them, so only Dylan's own Tailscale login gets a shell, and
//   3. any Origin header is this page's own address, so another website
//      open in his browser can't reach the terminal through his login.
// Everything else gets a short page saying why, which shows inside the
// Shell page's frame.
import http from 'node:http'
import net from 'node:net'

export const SHELL_PREFIX = '/shell'

/** True for /shell and anything under /shell/. */
export function isShellPath(url) {
  const { pathname } = new URL(url ?? '/', 'http://localhost')
  return pathname === SHELL_PREFIX || pathname.startsWith(`${SHELL_PREFIX}/`)
}

/**
 * Whether this request may reach the terminal. Returns null when it may,
 * or { status, message } saying why not.
 */
export function shellRefusal(req, config) {
  if (config.shellUsers.length === 0) {
    return { status: 404, message: 'The shell is off. Set SHELL_USERS in the server’s .env to your Tailscale login to turn it on.' }
  }
  const login = String(req.headers['tailscale-user-login'] ?? '').toLowerCase()
  if (!login) return { status: 403, message: 'Open this page through Tailscale to use the shell.' }
  if (!config.shellUsers.includes(login)) return { status: 403, message: `${login} isn’t allowed to use the shell.` }

  // Browsers send Origin on WebSockets and cross-site requests. It must be
  // this very page; a missing Origin (a same-site page load) is fine.
  const origin = req.headers.origin
  if (origin) {
    const host = req.headers.host ?? ''
    if (origin !== `https://${host}` && origin !== `http://${host}`) {
      return { status: 403, message: 'The shell only opens from this page.' }
    }
  }
  return null
}

/** The small page shown in the Shell frame instead of a terminal. */
function refusalPage(message) {
  return `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width">
<body style="margin:0;display:grid;place-items:center;height:100vh;background:#16212c;color:#f2efe9;font:15px system-ui;padding:24px;box-sizing:border-box">
<p style="max-width:42ch;text-align:center">${message.replace(/[<>&]/g, '')}</p></body>`
}

/** Writes a refusal: the page for normal requests, a bare status for WebSockets. */
function refuse(res, refusal) {
  res.statusCode = refusal.status
  res.setHeader('content-type', 'text/html; charset=utf-8')
  res.setHeader('cache-control', 'no-store')
  res.end(refusalPage(refusal.message))
}

/**
 * Creates the proxy. `request` handles normal HTTP (the terminal page and
 * its scripts); `upgrade` handles the WebSocket the terminal talks over.
 */
export function createShellProxy(config) {
  const target = new URL(config.shellUrl)
  const port = Number(target.port || 80)

  /** Proxies one HTTP request to ttyd, or refuses it. */
  function request(req, res) {
    const refusal = shellRefusal(req, config)
    if (refusal) return refuse(res, refusal)

    const upstream = http.request(
      { host: target.hostname, port, method: req.method, path: req.url, headers: req.headers },
      (answer) => {
        res.writeHead(answer.statusCode ?? 502, answer.headers)
        answer.pipe(res)
      },
    )
    upstream.on('error', () => refuse(res, { status: 502, message: 'The terminal (ttyd) isn’t running on jarvis. Start it with systemctl --user start ttyd.' }))
    req.pipe(upstream)
  }

  /**
   * Proxies the terminal's WebSocket. Node hands over the raw socket, so
   * the upgrade request is replayed to ttyd byte for byte and the two
   * sockets are then joined.
   */
  function upgrade(req, socket, head) {
    const refusal = shellRefusal(req, config)
    if (refusal) {
      socket.end(`HTTP/1.1 ${refusal.status} Refused\r\nConnection: close\r\n\r\n`)
      return
    }
    const upstream = net.connect(port, target.hostname, () => {
      let raw = `${req.method} ${req.url} HTTP/1.1\r\n`
      for (let i = 0; i < req.rawHeaders.length; i += 2) raw += `${req.rawHeaders[i]}: ${req.rawHeaders[i + 1]}\r\n`
      upstream.write(`${raw}\r\n`)
      if (head && head.length > 0) upstream.write(head)
      upstream.pipe(socket)
      socket.pipe(upstream)
    })
    // Either side closing ends the other, so no half-open sockets linger.
    upstream.on('error', () => socket.destroy())
    socket.on('error', () => upstream.destroy())
  }

  return { request, upgrade }
}
