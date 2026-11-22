import { describe, expect, it } from 'vitest'
import { canJoin, joinHeard, settledQuestion, heardWords } from '../../src/lib/heard'
import { stableCount } from '../../src/lib/talk'

const turns = [
  { id: 0, question: 'Hi.', answer: 'Hello.', done: true },
  { id: 1, question: 'Lights off', answer: '', done: false },
]

describe('canJoin', () => {
  it('joins onto the turn he is still answering', () => {
    expect(canJoin(turns, 1, true)).toBe(true)
  })
  it('never joins a plain new turn', () => {
    expect(canJoin(turns, 1, false)).toBe(false)
  })
  it('never joins once he has said something back', () => {
    expect(canJoin(turns, 0, true)).toBe(false)
  })
  it('never joins a turn that is gone', () => {
    expect(canJoin(turns, 7, true)).toBe(false)
  })
})

describe('joinHeard', () => {
  it('rewrites the open question in place and leaves the rest alone', () => {
    const joined = joinHeard(turns, 1, 'Lights off, and the fan too.')
    expect(joined[1]).toEqual({ id: 1, question: 'Lights off, and the fan too.', answer: '', done: false })
    expect(joined[0]).toEqual(turns[0])
    expect(joined).toHaveLength(2)
  })
})

describe('heardWords', () => {
  it('marks the first stable words settled and the tail not', () => {
    expect(heardWords('turn  the big light', 2)).toEqual([
      { word: 'turn', settled: true },
      { word: 'the', settled: true },
      { word: 'big', settled: false },
      { word: 'light', settled: false },
    ])
    expect(heardWords('turn the', 9).every((w) => w.settled)).toBe(true)
  })
  it('treats every word as unsettled when Jarvis sends no count', () => {
    expect(heardWords('turn the', null).some((w) => w.settled)).toBe(false)
    expect(heardWords('turn the', 0).some((w) => w.settled)).toBe(false)
    expect(heardWords('  ', 3)).toEqual([])
  })
})

describe('settledQuestion', () => {
  it('keeps the words on screen when the final says the same', () => {
    expect(settledQuestion('turn the big light off', 'Turn the big light off.', true)).toBe('turn the big light off')
  })
  it('takes the final when it differs, or when nothing was shown', () => {
    expect(settledQuestion('turn the big lied off', 'Turn the big light off.', false)).toBe('Turn the big light off.')
    expect(settledQuestion('', 'Turn the big light off.', true)).toBe('Turn the big light off.')
  })
})

describe('stableCount', () => {
  it('takes a whole number of zero or more, and nothing else', () => {
    expect(stableCount(3)).toBe(3)
    expect(stableCount(0)).toBe(0)
    expect(stableCount(-1)).toBeNull()
    expect(stableCount(1.5)).toBeNull()
    expect(stableCount(undefined)).toBeNull()
  })
})
