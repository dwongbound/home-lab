import { describe, expect, it } from 'vitest'
import { canJoin, joinHeard } from '../../src/lib/heard'

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
