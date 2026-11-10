// server/home.mjs: which HA entities become tiles, and the allow list that
// decides what the page may ask Home Assistant to do.
import { describe, expect, it } from 'vitest'
import { kindOf, parseHomeRequest, serviceCall, toDevices } from '../../server/home.mjs'

describe('toDevices', () => {
  it('keeps only controllable domains, scenes first, then by kind and name', () => {
    const devices = toDevices([
      { entity_id: 'switch.b_plug', state: 'off', attributes: { friendly_name: 'B plug' } },
      { entity_id: 'sensor.power', state: '12', attributes: {} },
      { entity_id: 'light.z_lamp', state: 'off', attributes: { friendly_name: 'Z lamp' } },
      { entity_id: 'light.a_lamp', state: 'off', attributes: { friendly_name: 'A lamp' } },
      { entity_id: 'scene.night', state: 'unknown', attributes: { friendly_name: 'Night' } },
      { entity_id: 'input_boolean.guest_mode', state: 'on', attributes: { friendly_name: 'Guest mode' } },
    ])
    expect(devices.map((d) => d.name)).toEqual(['Night', 'A lamp', 'Z lamp', 'B plug', 'Guest mode'])
    expect(devices.find((d) => d.name === 'Guest mode')).toMatchObject({ kind: 'switch', on: true })
  })

  it('reads what "on" means for each kind', () => {
    const [lock, cover, climate] = toDevices([
      { entity_id: 'lock.door', state: 'locked', attributes: {} },
      { entity_id: 'cover.garage', state: 'opening', attributes: {} },
      { entity_id: 'climate.house', state: 'cool', attributes: { current_temperature: 74, temperature: 72 } },
    ]).sort((a, b) => a.id.localeCompare(b.id)).reverse()
    expect(lock).toMatchObject({ kind: 'lock', on: true })
    expect(cover).toMatchObject({ kind: 'cover', on: true })
    expect(climate).toMatchObject({ kind: 'climate', on: true, temperature: 74, target: 72 })
  })

  it('dims only lights that can, and shows 0% while they are off', () => {
    const [dimOff, plain] = toDevices([
      { entity_id: 'light.a', state: 'off', attributes: { supported_color_modes: ['color_temp'] } },
      { entity_id: 'light.b', state: 'on', attributes: { supported_color_modes: ['onoff'] } },
    ])
    expect(dimOff.brightness).toBe(0)
    expect(plain.brightness).toBeNull()
  })

  it('marks unavailable devices, but a never-run scene is fine', () => {
    const [scene, light] = toDevices([
      { entity_id: 'light.a', state: 'unavailable', attributes: {} },
      { entity_id: 'scene.s', state: 'unknown', attributes: {} },
    ])
    expect(scene.unavailable).toBe(false)
    expect(light.unavailable).toBe(true)
  })
})

describe('the allow list', () => {
  it('knows which domains are tiles', () => {
    expect(kindOf('light.desk')).toBe('light')
    expect(kindOf('alarm_control_panel.house')).toBeNull()
    expect(kindOf('Light.Desk')).toBeNull()
  })

  it('accepts each kind only its own commands', () => {
    expect(parseHomeRequest({ id: 'lock.door', command: 'unlock' })).toEqual({ request: { id: 'lock.door', command: 'unlock' } })
    expect(parseHomeRequest({ id: 'lock.door', command: 'turn_off' }).error).toBeDefined()
    expect(parseHomeRequest({ id: 'scene.night', command: 'activate' }).request).toBeDefined()
    expect(parseHomeRequest({ id: 'switch.plug', command: 'brightness', value: 50 }).error).toBeDefined()
  })

  it('checks numbers', () => {
    expect(parseHomeRequest({ id: 'light.a', command: 'brightness', value: 49.6 })).toEqual({ request: { id: 'light.a', command: 'brightness', value: 50 } })
    expect(parseHomeRequest({ id: 'light.a', command: 'brightness', value: 0 }).error).toBe('Brightness is 1 to 100')
    expect(parseHomeRequest({ id: 'climate.house', command: 'temperature', value: '70' }).error).toBeDefined()
    expect(parseHomeRequest({ id: 'climate.house', command: 'temperature', value: 120 }).error).toBeDefined()
  })
})

describe('serviceCall', () => {
  it('maps each command to the HA service', () => {
    expect(serviceCall({ id: 'cover.garage', command: 'open' })).toEqual({ domain: 'cover', service: 'open_cover', data: { entity_id: 'cover.garage' } })
    expect(serviceCall({ id: 'scene.night', command: 'activate' })).toEqual({ domain: 'scene', service: 'turn_on', data: { entity_id: 'scene.night' } })
    expect(serviceCall({ id: 'climate.house', command: 'temperature', value: 70 }).data).toEqual({ entity_id: 'climate.house', temperature: 70 })
    expect(serviceCall({ id: 'input_boolean.guest', command: 'turn_on' }).domain).toBe('input_boolean')
  })
})
