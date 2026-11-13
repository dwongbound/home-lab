// Finding Jarvis's answer in the saved chat after the page lost the reply stream.
import { describe, expect, it } from 'vitest'
import { findAnswer } from '../../src/lib/chatCatchUp'
import type { ChatTurn } from '../../src/types'

const asked = Date.parse('2026-11-13T16:52:00Z')

describe('findAnswer', () => {
  it('finds his reply to the question once it is saved', () => {
    const lines: ChatTurn[] = [
      { role: 'user', text: 'Move Disneyland to Dec 8', at: '2026-11-13T16:52:01Z' },
      { role: 'jarvis', text: 'Moved it.', at: '2026-11-13T16:53:00Z' },
    ]
    expect(findAnswer(lines, ' Move Disneyland to Dec 8 ', asked)).toBe('Moved it.')
  })

  it('waits while he is still working', () => {
    const lines: ChatTurn[] = [{ role: 'user', text: 'Move Disneyland to Dec 8', at: '2026-11-13T16:52:01Z' }]
    expect(findAnswer(lines, 'Move Disneyland to Dec 8', asked)).toBeNull()
  })

  it('ignores the same question asked earlier in the day', () => {
    const lines: ChatTurn[] = [
      { role: 'user', text: 'What’s the weather?', at: '2026-11-13T09:00:00Z' },
      { role: 'jarvis', text: 'Old answer.', at: '2026-11-13T09:00:05Z' },
    ]
    expect(findAnswer(lines, 'What’s the weather?', asked)).toBeNull()
  })

  it('allows a little clock difference between the phone and the PC', () => {
    const lines: ChatTurn[] = [
      { role: 'user', text: 'Hi', at: '2026-11-13T16:51:10Z' },
      { role: 'jarvis', text: 'Hello.', at: '2026-11-13T16:51:12Z' },
    ]
    expect(findAnswer(lines, 'Hi', asked)).toBe('Hello.')
  })
})
