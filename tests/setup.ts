// Shared setup for the unit tests: jest-dom matchers (toBeInTheDocument...)
// and a clean DOM after each test.
import '@testing-library/jest-dom/vitest'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

// Newer Node has its own experimental localStorage, which is undefined
// without --localstorage-file and hides jsdom's. Use an in-memory one then.
if (typeof globalThis.localStorage?.clear !== 'function') {
  const items = new Map<string, string>()
  const storage: Storage = {
    get length() { return items.size },
    clear: () => items.clear(),
    getItem: (k) => items.get(String(k)) ?? null,
    key: (i) => [...items.keys()][i] ?? null,
    removeItem: (k) => { items.delete(String(k)) },
    setItem: (k, v) => { items.set(String(k), String(v)) },
  }
  Object.defineProperty(globalThis, 'localStorage', { value: storage, configurable: true, writable: true })
}

afterEach(() => {
  cleanup()
})
