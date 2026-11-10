// Small text helpers used across the page.

/** "Good morning" and friends, by hour. After midnight it's "Still up". */
export function greeting(date: Date): string {
  const h = date.getHours()
  if (h < 5) return 'Still up'
  if (h < 12) return 'Good morning'
  if (h < 17) return 'Good afternoon'
  return 'Good evening'
}

/** "6 days, 4 h", "3 h 12 min" or "8 min". */
export function uptime(sec: number): string {
  const d = Math.floor(sec / 86400)
  const h = Math.floor((sec % 86400) / 3600)
  const m = Math.floor((sec % 3600) / 60)
  if (d > 0) return `${d} ${d === 1 ? 'day' : 'days'}, ${h} h`
  if (h > 0) return `${h} h ${m} min`
  return `${m} min`
}

// Built once: Intl formatters are slow to create (Vercel rule js-cache-function-results).
const timeFmt = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit' })
/** "9:00 AM" in the viewer's time zone. */
export const clock = (iso: string) => timeFmt.format(new Date(iso))

/** "4 min ago", "2 h ago", "3 days ago". */
export function ago(iso: string, now: Date): string {
  const min = Math.round((now.getTime() - new Date(iso).getTime()) / 60_000)
  if (min < 1) return 'just now'
  if (min < 60) return `${min} min ago`
  const h = Math.round(min / 60)
  if (h < 24) return `${h} h ago`
  const d = Math.round(h / 24)
  return `${d} ${d === 1 ? 'day' : 'days'} ago`
}

/** value / total clamped to 0..1, or null if either is unknown. */
export function share(value: number | null, total: number | null): number | null {
  if (value == null || total == null || total <= 0) return null
  return Math.min(1, Math.max(0, value / total))
}

const USD = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD', maximumFractionDigits: 0 })
const USD_CENTS = new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' })

/** Dollars for the page: whole dollars for balances, cents when asked. */
export function dollars(n: number, cents = false): string {
  return (cents ? USD_CENTS : USD).format(n)
}
