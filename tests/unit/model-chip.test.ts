import { describe, expect, it } from 'vitest'
import { modelLabel, modelTone } from '../../src/lib/model'

describe('model chip', () => {
  it('names Jarvis with the initial of who answered', () => {
    expect(modelLabel('claude')).toBe('Jarvis (C)')
    expect(modelLabel('ornith')).toBe('Jarvis (O)')
    expect(modelLabel('  ')).toBe('')
  })
  it('colours Claude orange and anything local blue', () => {
    expect(modelTone('claude')).toBe('claude')
    expect(modelTone('Claude ')).toBe('claude')
    expect(modelTone('ornith')).toBe('local')
    expect(modelTone('qwen')).toBe('local')
  })
})
