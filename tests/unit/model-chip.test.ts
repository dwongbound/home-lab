import { describe, expect, it } from 'vitest'
import { modelLabel, modelTone } from '../../src/lib/model'

describe('model chip', () => {
  it('names Claude and the local model with a capital', () => {
    expect(modelLabel('claude')).toBe('Claude')
    expect(modelLabel('ornith')).toBe('Ornith')
    expect(modelLabel('  ')).toBe('')
  })
  it('colours Claude orange and anything local blue', () => {
    expect(modelTone('claude')).toBe('claude')
    expect(modelTone('Claude ')).toBe('claude')
    expect(modelTone('ornith')).toBe('local')
    expect(modelTone('qwen')).toBe('local')
  })
})
