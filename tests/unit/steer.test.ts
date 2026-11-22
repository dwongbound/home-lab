import { describe, expect, it } from 'vitest'
import { addFollowUp, dropFollowUp } from '../../src/lib/steer'

describe('messages sent while Jarvis is answering', () => {
  const turns = [{ id: 0 }, { id: 1, followUps: ['also the porch'] }]

  it('go under the turn being answered, in order', () => {
    const added = addFollowUp(addFollowUp(turns, 0, 'only the lamp'), 0, 'actually dim it')
    expect(added[0].followUps).toEqual(['only the lamp', 'actually dim it'])
    expect(added[1]).toBe(turns[1])
  })

  it('come back out one at a time when one turns into its own turn', () => {
    const twice = addFollowUp(addFollowUp(turns, 0, 'same'), 0, 'same')
    expect(dropFollowUp(twice, 0, 'same')[0].followUps).toEqual(['same'])
    expect(dropFollowUp(turns, 1, 'not there')[1].followUps).toEqual(['also the porch'])
    expect(dropFollowUp(turns, 0, 'nothing')[0]).toBe(turns[0])
  })
})
