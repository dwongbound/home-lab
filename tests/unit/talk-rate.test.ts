import { describe, expect, it } from 'vitest'
import { contextRate } from '../../src/lib/talk'

// Talk's audio runs at the microphone's rate, or iPhones crackle.
describe('contextRate', () => {
  it('follows the phone speaker rates', () => {
    expect(contextRate(48000)).toBe(48000)
    expect(contextRate(44100)).toBe(44100)
  })

  it('follows Bluetooth call-quality rates too (AirPods, car)', () => {
    expect(contextRate(16000)).toBe(16000)
    expect(contextRate(24000)).toBe(24000)
  })

  it('uses the default for a missing or odd rate', () => {
    expect(contextRate(undefined)).toBeNull()
    expect(contextRate(0)).toBeNull()
    expect(contextRate(Number.NaN)).toBeNull()
    expect(contextRate(384000)).toBeNull()
  })
})
