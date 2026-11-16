import { describe, expect, it } from 'vitest'
import { audioWasInterrupted, contextRate } from '../../src/lib/talk'

// Talk's audio runs at the microphone's rate, or iPhones crackle.
describe('contextRate', () => {
  it('follows the phone speaker rates', () => {
    expect(contextRate(48000)).toBe(48000)
    expect(contextRate(44100)).toBe(44100)
  })

  it('leaves call-quality rates to the browser default (following them crackled on the iPhone speaker)', () => {
    expect(contextRate(16000)).toBeNull()
    expect(contextRate(24000)).toBeNull()
  })

  it('uses the default for a missing or odd rate', () => {
    expect(contextRate(undefined)).toBeNull()
    expect(contextRate(0)).toBeNull()
    expect(contextRate(Number.NaN)).toBeNull()
    expect(contextRate(384000)).toBeNull()
  })
})

// A context iOS took away comes back crackling, so the line starts fresh instead.
describe('audioWasInterrupted', () => {
  it('is true when iOS takes the audio away', () => {
    expect(audioWasInterrupted('interrupted')).toBe(true)
    expect(audioWasInterrupted('suspended')).toBe(true)
  })

  it('is false while playing or after hanging up', () => {
    expect(audioWasInterrupted('running')).toBe(false)
    expect(audioWasInterrupted('closed')).toBe(false)
  })
})
