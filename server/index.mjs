// Production server: serves the built page from dist/ plus the API.
// Plain node:http with no framework, because jarvis has 16 GB of RAM and
// Gemma wants most of it.
import http from 'node:http'
import { readFile, stat } from 'node:fs/promises'
import { extname, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { loadConfig, loadEnvFile } from './config.mjs'
import { createApi, createSource } from './app.mjs'

loadEnvFile()
const config = loadConfig()
const api = createApi(createSource(config))
const distDir = resolve(fileURLToPath(new URL('../dist/', import.meta.url)))
const indexHtml = resolve(distDir, 'index.html')

const CONTENT_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.woff2': 'font/woff2',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.webp': 'image/webp',
}

/**
 * Maps a URL to a file in dist/. Anything that isn't a real file falls
 * back to index.html, and anything that resolves outside dist/ is refused.
 */
async function resolveFile(urlPath) {
  const wanted = resolve(distDir, '.' + decodeURIComponent(urlPath))
  const insideDist = wanted === distDir || wanted.startsWith(distDir + sep)
  if (!insideDist) return null
  try {
    const info = await stat(wanted)
    if (info.isFile()) return wanted
  } catch {
    // Not a file: fall through to the page.
  }
  return indexHtml
}

/** Serves one file from dist/. Hashed assets are cached forever. */
async function serveStatic(req, res) {
  const { pathname } = new URL(req.url ?? '/', 'http://localhost')
  const file = await resolveFile(pathname)
  if (file === null) {
    res.statusCode = 403
    return res.end()
  }
  try {
    const body = await readFile(file)
    res.setHeader('content-type', CONTENT_TYPES[extname(file)] ?? 'application/octet-stream')
    if (file.includes(`${sep}assets${sep}`)) {
      res.setHeader('cache-control', 'public, max-age=31536000, immutable')
    }
    res.end(body)
  } catch {
    res.statusCode = 404
    res.end('Not built yet. Run npm run build first.')
  }
}

http
  .createServer((req, res) => api(req, res, () => serveStatic(req, res)))
  .listen(config.port, config.host, () => {
    console.log(`home-lab on http://${config.host}:${config.port} (${config.dataSource} data)`)
  })
