// Which build of the page is running, for the thin footer (Dylan,
// 2026-11-16: "a way for me to know which build we're on").

/** The repo the commit link points at. */
const REPO_URL = 'https://github.com/dwongbound/home-lab'

/** A commit hash worth linking to: hex, 7 to 40 characters (not 'dev'). */
export function isCommit(sha: string): boolean {
  return /^[0-9a-f]{7,40}$/i.test(sha)
}

/** The GitHub page for a commit, or null when there's no real commit. */
export function commitUrl(sha: string): string | null {
  if (!isCommit(sha)) return null
  return `${REPO_URL}/commit/${sha}`
}

/** "Nov 16, 3:12 PM" in Pacific time, or '' if the date doesn't read. */
export function builtLabel(iso: string): string {
  const when = new Date(iso)
  if (Number.isNaN(when.getTime())) return ''
  return when.toLocaleString('en-US', {
    timeZone: 'America/Los_Angeles',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  })
}
