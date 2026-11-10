import type { MoneyAccount, MoneyTransaction } from '../types'

// Small rules for the Money page: tidying names Copilot sends, spotting
// purchases that still need a category, and grouping accounts.

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

/** A purchase Dylan still has to put in a real category in Copilot. Money coming in doesn't count. */
export function needsCategory(t: MoneyTransaction): boolean {
  if (t.amount <= 0) return false
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
