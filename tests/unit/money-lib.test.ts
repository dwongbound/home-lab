// The Money page's small rules: tidy names, purchases needing a category,
// account groups, and the detail links in the hash.
import { describe, expect, it } from 'vitest'
import { cleanText, groupAccounts, isEmptyAccount, needsCategory, onAccount } from '../../src/lib/money'
import { detailHref, parseDetail } from '../../src/useHashView'
import type { MoneyAccount, MoneyTransaction } from '../../src/types'

const tx = (over: Partial<MoneyTransaction>): MoneyTransaction => ({ id: 'x', date: '2026-11-10T00:00:00Z', merchant: 'M', category: 'Food', amount: 10, ...over })
const acct = (over: Partial<MoneyAccount>): MoneyAccount => ({ id: 'a', name: 'A', institution: 'Bank', kind: 'cash', balance: 1, ...over })

describe('money rules', () => {
  it('strips stray "undefined" and "null" words from names', () => {
    expect(cleanText('Joshua Lee "undefined"')).toBe('Joshua Lee')
    expect(cleanText('null Venmo  Alex')).toBe('Venmo Alex')
    expect(cleanText('Undefined Brewing')).toBe('Brewing')
    expect(cleanText('undefined')).toBe('undefined')
  })

  it('flags purchases in Other or with no category, never money coming in', () => {
    expect(needsCategory(tx({ category: 'Other' }))).toBe(true)
    expect(needsCategory(tx({ category: ' uncategorized ' }))).toBe(true)
    expect(needsCategory(tx({ category: '' }))).toBe(true)
    expect(needsCategory(tx({ category: 'Other', amount: -50 }))).toBe(false)
    expect(needsCategory(tx({ category: 'Food' }))).toBe(false)
  })

  it('groups accounts by kind, biggest first, with totals, and spots empty ones', () => {
    const groups = groupAccounts([
      acct({ id: '1', balance: 5 }), acct({ id: '2', balance: 50 }), acct({ id: '3', kind: 'credit', balance: 9 }),
    ])
    expect(groups.map((g) => g.label)).toEqual(['Cash', 'Cards'])
    expect(groups[0].accounts.map((a) => a.id)).toEqual(['2', '1'])
    expect(groups[0].total).toBe(55)
    expect(isEmptyAccount(acct({ balance: 0 }))).toBe(true)
    expect(isEmptyAccount(acct({ balance: 0.01 }))).toBe(false)
  })

  it('finds an account’s transactions by id, or by name when there is no id', () => {
    const a = acct({ id: 'm1', name: 'Checking' })
    const items = [tx({ id: '1', accountId: 'm1' }), tx({ id: '2', account: 'Checking' }), tx({ id: '3', accountId: 'm2', account: 'Checking' })]
    expect(onAccount(items, a).map((t) => t.id)).toEqual(['1', '2'])
  })

  it('builds and reads detail links, escaping ids', () => {
    expect(detailHref('money', 't', 'x1')).toBe('#money/t/x1')
    expect(detailHref('money', 'sort')).toBe('#money/sort')
    expect(detailHref('money', 'c', 'Food & drink')).toBe('#money/c/Food%20%26%20drink')
    expect(parseDetail('c/Food%20%26%20drink')).toEqual({ kind: 'c', id: 'Food & drink' })
    expect(parseDetail('sort')).toEqual({ kind: 'sort', id: '' })
    expect(parseDetail('t/%E0%A4%A')).toEqual({ kind: 't', id: '%E0%A4%A' })
  })
})
