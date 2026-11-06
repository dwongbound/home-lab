// End-to-end tests against the real production server (built page + API,
// mock data), on a desktop and a phone-sized browser.
import { defineConfig, devices } from '@playwright/test'

const PORT = 4181

export default defineConfig({
  testDir: 'tests/e2e',
  // The mock source keeps Gemma's loaded state in the one server process,
  // so tests run one at a time to not trip over each other.
  workers: 1,
  fullyParallel: false,
  reporter: process.env.CI ? 'github' : 'list',
  use: {
    baseURL: `http://127.0.0.1:${PORT}`,
    timezoneId: 'America/Los_Angeles',
    trace: 'off',
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'], viewport: { width: 1440, height: 1000 } } },
    { name: 'phone', use: { ...devices['Pixel 7'] } },
  ],
  webServer: {
    command: `npm run build && PORT=${PORT} DATA_SOURCE=mock node server/index.mjs`,
    url: `http://127.0.0.1:${PORT}/api/snapshot`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
})
