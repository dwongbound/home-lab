import { execSync } from 'node:child_process'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'
import { loadConfig, loadEnvFile } from './server/config.mjs'
import { createApi, createSource } from './server/app.mjs'

// Vite config. The dev server mounts the real API handler, so `npm run dev`
// and `npm start` answer /api/* with the same code.

/** Vite plugin that serves /api/* from server/app.mjs during development. */
function apiPlugin(): Plugin {
  return {
    name: 'home-lab-api',
    configureServer(server) {
      loadEnvFile()
      const api = createApi(createSource(loadConfig()))
      server.middlewares.use((req, res, next) => api(req, res, next))
    },
  }
}

/**
 * The commit this build is from, for the footer. Docker passes GIT_SHA in
 * (the image has no .git); elsewhere git is asked; 'dev' if neither works.
 */
function gitSha(): string {
  if (process.env.GIT_SHA) return process.env.GIT_SHA
  try {
    return execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return 'dev'
  }
}

export default defineConfig({
  plugins: [react(), apiPlugin()],
  // Which build the page is (BuildFooter). BUILT_AT comes from the deploy
  // command; otherwise the moment this build ran.
  define: {
    __BUILD_SHA__: JSON.stringify(gitSha()),
    __BUILT_AT__: JSON.stringify(process.env.BUILT_AT || new Date().toISOString()),
  },
  base: './',
  server: { port: 5180 },
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    css: false,
    include: ['tests/unit/**/*.test.{ts,tsx}'],
  },
})
