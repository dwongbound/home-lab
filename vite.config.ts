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

export default defineConfig({
  plugins: [react(), apiPlugin()],
  base: './',
  server: { port: 5180 },
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'],
    css: false,
    include: ['tests/unit/**/*.test.{ts,tsx}'],
  },
})
