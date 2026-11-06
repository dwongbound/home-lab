// Reads the cloud digest: one JSON file that a scheduled Claude task writes
// to a private GitHub repo every hour (see docs/digest.md). The PC can't
// reach claude.ai threads or Dylan's connectors itself, so this file is how
// they get here.
//
// It's fetched at most every 5 minutes, however often the page refreshes,
// and the last good copy is kept if GitHub is unreachable.

const CACHE_MS = 5 * 60_000
const FETCH_TIMEOUT_MS = 5000

/**
 * Creates the digest reader. Returns null from read() when no token is set,
 * which the page shows as "not set up yet".
 * `deps.fetch` and `deps.now` are swappable for tests.
 */
export function createDigestReader(config, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch
  const now = deps.now ?? (() => Date.now())
  let cached = null
  let cachedAt = 0

  /** The GitHub contents API URL for digest.json on the configured branch. */
  function digestUrl() {
    const { digestRepo, digestBranch, digestPath } = config
    return `https://api.github.com/repos/${digestRepo}/contents/${digestPath}?ref=${encodeURIComponent(digestBranch)}`
  }

  /** Downloads and parses the digest. Throws on any failure. */
  async function download() {
    const res = await fetchFn(digestUrl(), {
      headers: {
        Authorization: `Bearer ${config.digestToken}`,
        // "raw" returns the file itself instead of base64 inside JSON.
        Accept: 'application/vnd.github.raw+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'home-lab',
      },
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
    })
    if (!res.ok) throw new Error(`GitHub answered ${res.status}`)
    return res.json()
  }

  return {
    /** The digest, from cache when it's under 5 minutes old. */
    async read() {
      if (!config.digestToken) return null
      if (cached !== null && now() - cachedAt < CACHE_MS) return cached
      try {
        cached = await download()
        cachedAt = now()
      } catch {
        // Keep showing the last good copy; its updatedAt says how old it is.
        // Try again on the next refresh rather than waiting 5 minutes.
      }
      return cached
    },
  }
}
