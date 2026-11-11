import type { MoneyAccount, MoneyPick, MoneyPicks, MoneyTransaction } from '../types'

// Small rules for the Money page: tidying names Copilot sends, spotting
// purchases that still need a category, and grouping accounts, and the categories picked on the page
// until they're applied in Copilot.

/** Copilot sometimes sends the words "undefined" or "null" inside a name (from Venmo notes). */
export function cleanText(text: string): string {
  const cleaned = text
    .replace(/["“”']?\b(undefined|null)\b["“”']?/gi, '')
    .replace(/\s{2,}/g, ' ')
    .trim()
  if (cleaned === '') return text.trim()
  return cleaned
}

// Categories that mean "not sorted yet".
const UNSORTED = new Set(['', 'other', 'uncategorized', 'uncategorised'])

/**
 * A purchase Dylan still has to put in a real category in Copilot. Money
 * coming in doesn't count, and neither does money moved between his own
 * accounts (Copilot's internal transfers).
 */
export function needsCategory(t: MoneyTransaction): boolean {
  if (t.amount <= 0) return false
  if (t.type === 'transfer') return false
  return UNSORTED.has(t.category.trim().toLowerCase())
}

/** An account holding nothing (closed, or never used). */
export function isEmptyAccount(a: MoneyAccount): boolean {
  return Math.abs(a.balance) < 0.005
}

export interface AccountGroup { kind: MoneyAccount['kind']; label: string; accounts: MoneyAccount[]; total: number }

const GROUPS: { kind: MoneyAccount['kind']; label: string }[] = [
  { kind: 'cash', label: 'Cash' },
  { kind: 'credit', label: 'Cards' },
  { kind: 'investment', label: 'Investments' },
  { kind: 'loan', label: 'Loans' },
  { kind: 'other', label: 'Other' },
]

/** Accounts by kind, biggest balance first, leaving out empty groups. */
export function groupAccounts(accounts: MoneyAccount[]): AccountGroup[] {
  const groups: AccountGroup[] = []
  for (const g of GROUPS) {
    const inGroup = accounts.filter((a) => a.kind === g.kind).toSorted((a, b) => b.balance - a.balance)
    if (inGroup.length === 0) continue
    let total = 0
    for (const a of inGroup) total += a.balance
    groups.push({ ...g, accounts: inGroup, total })
  }
  return groups
}

/** The transactions on one account, matched by id when the digest has it, else by name. */
export function onAccount(recent: MoneyTransaction[], account: MoneyAccount): MoneyTransaction[] {
  return recent.filter((t) => t.accountId === account.id || (t.accountId === undefined && t.account === account.name))
}

/** The picks keyed by purchase id. */
export function picksById(picks: MoneyPick[]): Map<string, MoneyPick> {
  return new Map(picks.map((p) => [p.id, p]))
}

/** Purchases still needing a category that haven't been given one on the page yet. */
export function stillToPick(recent: MoneyTransaction[], picks: MoneyPick[]): MoneyTransaction[] {
  const picked = picksById(picks)
  return recent.filter((t) => needsCategory(t) && !picked.has(t.id))
}

export interface PickGroup { category: string; picks: MoneyPick[] }

/** Picks grouped by category (A to Z), newest purchase first in each, for one sitting in Copilot. */
export function groupPicks(picks: MoneyPick[]): PickGroup[] {
  const groups = new Map<string, MoneyPick[]>()
  for (const p of picks) {
    const list = groups.get(p.category) ?? []
    list.push(p)
    groups.set(p.category, list)
  }
  const names = [...groups.keys()].toSorted((a, b) => a.localeCompare(b))
  return names.map((category) => ({
    category,
    picks: (groups.get(category) ?? []).toSorted((a, b) => b.date.localeCompare(a.date)),
  }))
}

/** Categories to offer when picking: Copilot's from the digest, then ones used before. */
export function categoryChoices(digestCategories: string[], picks: MoneyPick[]): string[] {
  const seen = new Set<string>()
  const choices: string[] = []
  for (const name of [...digestCategories, ...picks.map((p) => p.category)]) {
    const key = name.trim().toLowerCase()
    if (key === '' || UNSORTED.has(key) || seen.has(key)) continue
    seen.add(key)
    choices.push(name.trim())
  }
  return choices
}

// Reminders go off in the evening, after work.
const REMIND_HOUR = 20

/** `days` from now at 8 PM local time. */
function eveningIn(now: Date, days: number): Date {
  const at = new Date(now)
  at.setDate(at.getDate() + days)
  at.setHours(REMIND_HOUR, 0, 0, 0)
  return at
}

export interface ReminderChoice { label: string; at: Date }

/** When the reminder can go off: tonight (while it's still before 8 PM), tomorrow, or in 3 days. */
export function reminderChoices(now: Date): ReminderChoice[] {
  const choices: ReminderChoice[] = []
  const tonight = eveningIn(now, 0)
  if (tonight.getTime() > now.getTime()) choices.push({ label: 'Tonight', at: tonight })
  choices.push({ label: 'Tomorrow', at: eveningIn(now, 1) })
  choices.push({ label: 'In 3 days', at: eveningIn(now, 3) })
  return choices
}

/** The reminder a first pick sets: tomorrow evening. */
export function defaultReminder(now: Date): Date {
  return eveningIn(now, 1)
}

/** True once there are picks waiting and their reminder time has come. */
export function pickReminderDue(picks: MoneyPicks, now: Date): boolean {
  if (picks.picks.length === 0 || picks.remindAt === null) return false
  return Date.parse(picks.remindAt) <= now.getTime()
}
