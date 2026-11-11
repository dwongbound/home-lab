// server/talk.mjs: who may open the Talk line, and that the proxy carries
// the WebSocket through to Jarvis's /talk/ws?chat=web with the login.
import http from 'node:http'
import net from 'node:net'
import type { AddressInfo } from 'node:net'
import { afterEach, describe, expect, it } from 'vitest'
import { createTalkProxy, isTalkPath, talkRefusal } from '../../server/talk.mjs'
import { loadConfig } from '../../server/config.mjs'

const ME = 'dylan@example.com'
const HOST = 'jarvis.example.ts.net'

/** A fake request with the given headers. */
const req = (headers: Record<string, string>) => ({ headers }) as any

describe('who may talk', () => {
  it('needs a Tailscale login and this page as the origin', () => {
    expect(talkRefusal(req({ host: HOST, origin: `https://${HOST}`, 'tailscale-user-login': ME }))).toBeNull()
    expect(talkRefusal(req({ host: HOST, origin: `https://${HOST}` }))).toBe(403)
    expect(talkRefusal(req({ host: HOST, 'tailscale-user-login': ME }))).toBe(403)
    expect(talkRefusal(req({ host: HOST, origin: 'https://evil.example', 'tailscale-user-login': ME }))).toBe(403)
  })

  it('knows its path', () => {
    expect(isTalkPath('/api/jarvis/talk')).toBe(true)
    expect(isTalkPath('/api/jarvis/talk?x=1')).toBe(true)
    expect(isTalkPath('/api/jarvis/talking')).toBe(false)
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

  it('rewrites the path for Jarvis, passes the login, and joins the sockets', async () => {
    let seen = { url: '', login: '' }
    const jarvis = http.createServer()
    jarvis.on('upgrade', (r, socket) => {
      seen = { url: r.url ?? '', login: String(r.headers['tailscale-user-login'] ?? '') }
      socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n')
      socket.on('data', (d) => socket.write(`echo:${d}`))
    })
    const jarvisPort = await listen(jarvis)
    const talk = createTalkProxy(loadConfig({ JARVIS_API_URL: `http://127.0.0.1:${jarvisPort}` }))
    const front = http.createServer()
    front.on('upgrade', talk.upgrade)
    const port = await listen(front)

    /** Sends a raw upgrade and resolves with everything received. */
    const upgrade = (extra: string) => new Promise<string>((done) => {
      const s = net.connect(port, '127.0.0.1', () => {
        s.write(`GET /api/jarvis/talk HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n${extra}\r\n`)
        setTimeout(() => s.write('pcm'), 50)
      })
      let got = ''
      s.on('data', (d) => { got += d })
      setTimeout(() => { s.destroy(); done(got) }, 200)
      s.on('close', () => done(got))
    })

    const allowed = await upgrade(`Origin: http://127.0.0.1:${port}\r\nTailscale-User-Login: ${ME}\r\n`)
    expect(allowed).toContain('101 Switching Protocols')
    expect(allowed).toContain('echo:pcm')
    expect(seen).toEqual({ url: '/talk/ws?chat=web', login: ME })

    const refused = await upgrade('Origin: https://evil.example\r\nTailscale-User-Login: dylan@example.com\r\n')
    expect(refused).toContain('403')
    expect(refused).not.toContain('echo:')
  })
})
