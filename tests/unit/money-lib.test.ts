// The Money page's small rules: tidy names, purchases needing a category,
// account groups, and the detail links in the hash.
import { describe, expect, it } from 'vitest'
import { categoryChoices, cleanText, groupAccounts, groupPicks, isEmptyAccount, needsCategory, onAccount, pickReminderDue, reminderChoices, stillToPick } from '../../src/lib/money'
import { detailHref, parseDetail } from '../../src/useHashView'
import type { MoneyAccount, MoneyPick, MoneyTransaction } from '../../src/types'

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
    // A move between his own accounts never needs a category.
    expect(needsCategory(tx({ category: '', type: 'transfer' }))).toBe(false)
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

const pick = (over: Partial<MoneyPick>): MoneyPick => ({ id: 'x', category: 'Food', merchant: 'M', date: '2026-11-10T00:00:00Z', amount: 10, pickedAt: '2026-11-10T01:00:00Z', ...over })

describe('category picks', () => {
  it('leaves picked purchases out of the ones still to pick', () => {
    const recent = [tx({ id: 'a', category: 'Other' }), tx({ id: 'b', category: '' }), tx({ id: 'c' })]
    expect(stillToPick(recent, [pick({ id: 'a' })]).map((t) => t.id)).toEqual(['b'])
  })

  it('groups picks by category, A to Z, newest first in each', () => {
    const groups = groupPicks([
      pick({ id: '1', category: 'Travel', date: '2026-11-01T00:00:00Z' }),
      pick({ id: '2', category: 'Gifts', date: '2026-11-02T00:00:00Z' }),
      pick({ id: '3', category: 'Travel', date: '2026-11-05T00:00:00Z' }),
    ])
    expect(groups.map((g) => g.category)).toEqual(['Gifts', 'Travel'])
    expect(groups[1].picks.map((p) => p.id)).toEqual(['3', '1'])
  })

  it('offers Copilot categories, then ones used before, without Other or repeats', () => {
    expect(categoryChoices(['Food', 'Other', 'Shopping'], [pick({ category: 'food' }), pick({ category: 'Lessons' })])).toEqual(['Food', 'Shopping', 'Lessons'])
  })

  it('offers tonight only before 8 PM, then tomorrow and in 3 days, all at 8 PM', () => {
    const afternoon = new Date(2026, 10, 10, 17, 0)
    const choices = reminderChoices(afternoon)
    expect(choices.map((c) => c.label)).toEqual(['Tonight', 'Tomorrow', 'In 3 days'])
    expect(choices.map((c) => [c.at.getDate(), c.at.getHours()])).toEqual([[10, 20], [11, 20], [13, 20]])
    expect(reminderChoices(new Date(2026, 10, 10, 21, 0)).map((c) => c.label)).toEqual(['Tomorrow', 'In 3 days'])
  })

  it('is due only with picks waiting and the time come', () => {
    const now = new Date('2026-11-11T05:00:00Z')
    expect(pickReminderDue({ picks: [pick({})], remindAt: '2026-11-11T04:00:00Z' }, now)).toBe(true)
    expect(pickReminderDue({ picks: [pick({})], remindAt: '2026-11-11T06:00:00Z' }, now)).toBe(false)
    expect(pickReminderDue({ picks: [], remindAt: '2026-11-11T04:00:00Z' }, now)).toBe(false)
  })
})
