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
      dailyUsd: 6, spentUsd: 2.41, level: 'slow',
      today: [{ kind: 'judge', usd: 1.2, calls: 14 }, { kind: 'lookout', usd: 0.5, calls: 3 }],
      days: [{ date: '2026-11-25', usd: 4.76 }, { date: '2026-11-26', usd: 2.41 }],
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

  it('is null without the budget or the spend', () => {
    expect(parseClaudeUsage(null)).toBeNull()
    expect(parseClaudeUsage({ daily_usd: 6 })).toBeNull()
    expect(parseClaudeUsage({ daily_usd: -1, spent_usd: 2 })).toBeNull()
  })

  it('is in the sample snapshot with seven days', async () => {
    const snapshot = await createMockSource().snapshot()
    expect(snapshot.claudeUsage?.days.length).toBe(7)
    expect(snapshot.claudeUsage?.spentUsd).toBeLessThan(snapshot.claudeUsage?.dailyUsd ?? 0)
  })
})
