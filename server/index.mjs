// Production server: the API the Jarvis apps use, the reports, the terminal
// and Talk's WebSocket. Plain node:http with no framework, because jarvis
// needs its memory for the local model and voice.
import http from 'node:http'
import { loadConfig, loadEnvFile } from './config.mjs'
import { createApi, createSource } from './app.mjs'
import { createShellProxy, isShellPath } from './shell.mjs'
import { createTalkProxy, isTalkPath } from './talk.mjs'

loadEnvFile()
const config = loadConfig()
const api = createApi(createSource(config))
const shell = createShellProxy(config)
const talk = createTalkProxy(config)

/** Routes a request: the terminal under /shell/, else the API (which also draws /). */
function handle(req, res) {
  if (isShellPath(req.url)) return shell.request(req, res)
  return api(req, res)
}

const server = http.createServer(handle)
// The terminal's and Talk's WebSockets arrive as upgrades, not normal requests.
server.on('upgrade', (req, socket, head) => {
  if (isShellPath(req.url)) return shell.upgrade(req, socket, head)
  if (isTalkPath(req.url)) return talk.upgrade(req, socket, head)
  socket.destroy()
})
server.listen(config.port, config.host, () => {
  console.log(`home-lab on http://${config.host}:${config.port} (${config.dataSource} data)`)
})
