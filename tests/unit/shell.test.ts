// server/shell.mjs: who gets a terminal, and that the proxy really carries
// both the terminal page and its WebSocket through to ttyd.
import http from 'node:http'
import net from 'node:net'
import type { AddressInfo } from 'node:net'
import { afterEach, describe, expect, it } from 'vitest'
import { createShellProxy, isShellPath, shellRefusal } from '../../server/shell.mjs'
import { loadConfig } from '../../server/config.mjs'

const ME = 'dylan@example.com'
const config = loadConfig({ SHELL_USERS: `${ME}, other@example.com` })

/** A fake request with the given headers. */
const req = (headers: Record<string, string>) => ({ headers }) as any

describe('who gets a shell', () => {
  it('nobody when SHELL_USERS is empty', () => {
    expect(shellRefusal(req({ 'tailscale-user-login': ME }), loadConfig({}))?.status).toBe(404)
  })

  it('only listed Tailscale logins, any case', () => {
    expect(shellRefusal(req({ host: 'jarvis', 'tailscale-user-login': 'Dylan@Example.com' }), config)).toBeNull()
    expect(shellRefusal(req({ host: 'jarvis' }), config)?.status).toBe(403)
    expect(shellRefusal(req({ host: 'jarvis', 'tailscale-user-login': 'stranger@example.com' }), config)?.status).toBe(403)
  })

  it('refuses another website reaching it through his login', () => {
    const headers = { host: 'jarvis.example.ts.net', 'tailscale-user-login': ME }
    expect(shellRefusal(req({ ...headers, origin: 'https://evil.example' }), config)?.status).toBe(403)
    expect(shellRefusal(req({ ...headers, origin: 'https://jarvis.example.ts.net' }), config)).toBeNull()
  })

  it('knows its paths', () => {
    expect(isShellPath('/shell/')).toBe(true)
    expect(isShellPath('/shell/ws?x=1')).toBe(true)
    expect(isShellPath('/shellfish')).toBe(false)
  })
})

describe('the proxy', () => {
  const servers: http.Server[] = []
  afterEach(() => { for (const s of servers.splice(0)) s.close() })

  /** Listens on a free port and resolves with it. */
  async function listen(server: http.Server): Promise<number> {
    servers.push(server)
    await new Promise<void>((done) => server.listen(0, '127.0.0.1', done))
    return (server.address() as AddressInfo).port
  }

  /** A stand-in ttyd (page + echoing WebSocket upgrade) and the proxy in front of it. */
  async function setUp() {
    const ttyd = http.createServer((r, res) => res.end(`ttyd page at ${r.url}`))
    ttyd.on('upgrade', (_r, socket) => {
      socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
      socket.on('data', (d) => socket.write(`echo:${d}`))
    })
    const ttydPort = await listen(ttyd)
    const shell = createShellProxy(loadConfig({ SHELL_USERS: ME, SHELL_URL: `http://127.0.0.1:${ttydPort}` }))
    const front = http.createServer(shell.request)
    front.on('upgrade', shell.upgrade)
    return listen(front)
  }

  it('serves the terminal page to an allowed login, and a refusal page otherwise', async () => {
    const port = await setUp()
    const ok = await fetch(`http://127.0.0.1:${port}/shell/`, { headers: { 'tailscale-user-login': ME } })
    expect(await ok.text()).toBe('ttyd page at /shell/')
    const no = await fetch(`http://127.0.0.1:${port}/shell/`)
    expect(no.status).toBe(403)
    expect(await no.text()).toContain('Open this page through Tailscale')
  })

  it('joins the WebSocket through to ttyd, and closes it for strangers', async () => {
    const port = await setUp()
    /** Sends a raw upgrade and resolves with everything received. */
    const upgrade = (login: string) => new Promise<string>((done) => {
      const s = net.connect(port, '127.0.0.1', () => {
        s.write(`GET /shell/ws HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nTailscale-User-Login: ${login}\r\n\r\n`)
        setTimeout(() => s.write('ls'), 50)
      })
      let got = ''
      s.on('data', (d) => { got += d })
      setTimeout(() => { s.destroy(); done(got) }, 200)
      s.on('close', () => done(got))
    })
    const allowed = await upgrade(ME)
    expect(allowed).toContain('101 Switching Protocols')
    expect(allowed).toContain('echo:ls')
    const refused = await upgrade('stranger@example.com')
    expect(refused).toContain('403')
    expect(refused).not.toContain('echo:')
  })
})
