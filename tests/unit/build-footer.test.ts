import { describe, expect, it } from 'vitest'
import { builtLabel, commitUrl, isCommit } from '../../src/lib/build'

// The faint build line at the bottom of the page.
describe('build footer', () => {
  it('links a real commit to GitHub and leaves "dev" plain', () => {
    expect(isCommit('3bf3d03')).toBe(true)
    expect(commitUrl('3bf3d03')).toBe('https://github.com/dwongbound/home-lab/commit/3bf3d03')
    expect(commitUrl('dev')).toBeNull()
    expect(commitUrl('')).toBeNull()
  })

  it('shows when it was deployed in Pacific time', () => {
    expect(builtLabel('2026-11-16T23:12:00Z')).toBe('Nov 16, 3:12 PM')
    expect(builtLabel('2026-11-16T15:12:00-08:00')).toBe('Nov 16, 3:12 PM')
    expect(builtLabel('')).toBe('')
    expect(builtLabel('not a date')).toBe('')
  })
})
