import { describe, expect, it } from 'vitest'
import { parseClaudeUsage } from '../../server/sources/claude-usage.mjs'
import { createMockSource } from '../../server/sources/mock.mjs'

describe('parseClaudeUsage', () => {
  it("renames Jarvis's answer, biggest kind first and days oldest first", () => {
    const usage = parseClaudeUsage({
      daily_usd: 6, spent_usd: 2.414, level: 'slow',
      today: [{ kind: 'lookout', usd: 0.5, calls: 3 }, { kind: ' judge ', usd: 1.2, calls: 14.7 }, { kind: '', usd: 1 }, { kind: 'bad', usd: 'x' }],
      days: [{ date: '2026-11-26', usd: 2.41 }, { date: '2026-11-25', usd: 4.756 }, { date: 'yesterday', usd: 1 }],
    })
    expect(usage).toEqual({
      dailyUsd: 6, spentUsd: 2.41, level: 'slow', limits: null,
      today: [{ kind: 'judge', usd: 1.2, tokens: null, calls: 14 }, { kind: 'lookout', usd: 0.5, tokens: null, calls: 3 }],
      days: [{ date: '2026-11-25', usd: 4.76, tokens: null }, { date: '2026-11-26', usd: 2.41, tokens: null }],
    })
  })

  it('keeps only the last seven days and treats an unknown level as ok', () => {
    const days = Array.from({ length: 9 }, (_, i) => ({ date: `2026-11-1${i}`, usd: i }))
    const usage = parseClaudeUsage({ daily_usd: 6, spent_usd: 0, level: 'panic', days })
    expect(usage?.level).toBe('ok')
    expect(usage?.days.length).toBe(7)
    expect(usage?.days[0].date).toBe('2026-11-12')
    expect(usage?.today).toEqual([])
  })

  it('passes on plan limits and tokens when Jarvis sends them', () => {
    const usage = parseClaudeUsage({
      daily_usd: 6, spent_usd: 1,
      limits: [{ name: 'session', used_pct: 6.4, resets_at: '2026-11-26T19:20:00-08:00' }, { name: 'weekly', used_pct: 136 }, { name: 'monthly', used_pct: 5 }, { name: 'session', used_pct: 'x' }],
      today: [{ kind: 'chat', usd: 1.9, tokens: 2400000.4, calls: 22 }],
      days: [{ date: '2026-11-26', usd: 1, tokens: 1200000 }],
    })
    expect(usage?.limits).toEqual([{ name: 'session', usedPct: 6, resetsAt: '2026-11-26T19:20:00-08:00' }, { name: 'weekly', usedPct: 100, resetsAt: null }])
    expect(usage?.today).toEqual([{ kind: 'chat', usd: 1.9, tokens: 2400000, calls: 22 }])
    expect(usage?.days).toEqual([{ date: '2026-11-26', usd: 1, tokens: 1200000 }])
    expect(parseClaudeUsage({ daily_usd: 6, spent_usd: 1, limits: [] })?.limits).toBeNull()
  })

  it('is null without the budget or the spend', () => {
    expect(parseClaudeUsage(null)).toBeNull()
    expect(parseClaudeUsage({ daily_usd: 6 })).toBeNull()
    expect(parseClaudeUsage({ daily_usd: -1, spent_usd: 2 })).toBeNull()
  })

  it('is in the sample snapshot with seven days', async () => {
    const snapshot = await createMockSource().snapshot()
    expect(snapshot.claudeUsage?.days.length).toBe(7)
    expect(snapshot.claudeUsage?.spentUsd).toBeLessThan(snapshot.claudeUsage?.dailyUsd ?? 0)
    expect(snapshot.claudeUsage?.limits?.map((limit) => limit.name)).toEqual(['session', 'weekly'])
  })
})
