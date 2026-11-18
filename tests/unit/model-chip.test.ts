import { describe, expect, it } from 'vitest'
import { modelLabel, modelTone } from '../../src/lib/model'

describe('model chip', () => {
  it('names Jarvis with the initial of who answered', () => {
    expect(modelLabel('claude')).toBe('Jarvis (C)')
    expect(modelLabel('ornith')).toBe('Jarvis (O)')
    expect(modelLabel('  ')).toBe('')
  })
  it('adds a second letter for which Claude model answered', () => {
    expect(modelLabel('claude-opus-5-5')).toBe('Jarvis (CO)')
    expect(modelLabel('claude-haiku-5-5')).toBe('Jarvis (CH)')
    expect(modelLabel('claude-sonnet-5-5')).toBe('Jarvis (CS)')
    expect(modelLabel('claude-fable-5-2')).toBe('Jarvis (CF)')
    expect(modelLabel('Opus')).toBe('Jarvis (CO)')
    expect(modelLabel('ornith-1.5:9b')).toBe('Jarvis (O)')
  })
  it('colours Claude orange and anything local blue', () => {
    expect(modelTone('claude')).toBe('claude')
    expect(modelTone('Claude ')).toBe('claude')
    expect(modelTone('ornith')).toBe('local')
    expect(modelTone('claude-opus-5-5')).toBe('claude')
    expect(modelTone('haiku')).toBe('claude')
    expect(modelTone('qwen')).toBe('local')
  })
})
