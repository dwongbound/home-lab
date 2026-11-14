import { describe, expect, it } from 'vitest'
import { thermoActivity, thermoStatus } from '../../src/lib/thermostat'
import type { Device } from '../../src/types'

/** A thermostat device with just the fields these rules read. */
function thermo(over: Partial<Device>): Device {
  return { id: 'climate.t', name: 'Thermostat', kind: 'climate', state: 'cool', available: true, current: 77, target: 77, ...over } as Device
}

describe('thermostat activity', () => {
  it('cools while the room is warmer than the setting, and holds once it gets there', () => {
    expect(thermoStatus(thermo({ current: 79, target: 76 }))).toBe('Cooling to 76°')
    expect(thermoStatus(thermo({ current: 77, target: 77 }))).toBe('Holding at 77°')
    expect(thermoActivity(thermo({ current: 75, target: 77 }))).toBe('idle')
  })

  it('heats while the room is cooler than the setting', () => {
    expect(thermoStatus(thermo({ state: 'heat', current: 66, target: 70 }))).toBe('Heating to 70°')
    expect(thermoActivity(thermo({ state: 'heat', current: 72, target: 70 }))).toBe('idle')
  })

  it('Heat/Cool works either way, and Off is off', () => {
    expect(thermoActivity(thermo({ state: 'heat_cool', current: 66, target: 70 }))).toBe('heating')
    expect(thermoActivity(thermo({ state: 'heat_cool', current: 74, target: 70 }))).toBe('cooling')
    expect(thermoStatus(thermo({ state: 'off' }))).toBe('Off')
  })

  it('believes the thermostat when it says what it is doing', () => {
    expect(thermoActivity(thermo({ current: 79, target: 76, detail: 'idle' }))).toBe('idle')
    expect(thermoActivity(thermo({ state: 'heat', current: 72, target: 70, detail: 'heating' }))).toBe('heating')
  })
})
