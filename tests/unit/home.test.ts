// Home Assistant control: which devices show, and that the page can only
// send the few commands it's meant to, to the kinds of device it's meant to.
import { describe, expect, it, vi } from 'vitest'
import { createHomeReader, toDevice } from '../../server/sources/home.mjs'
import { createLiveSource } from '../../server/sources/live.mjs'
import { loadConfig } from '../../server/config.mjs'

const config = loadConfig({ DATA_SOURCE: 'live', HA_TOKEN: 'token' })

const STATES = [
  { entity_id: 'light.lamp', state: 'on', attributes: { friendly_name: 'Lamp', brightness: 153 } },
  { entity_id: 'media_player.tv', state: 'playing', attributes: { friendly_name: 'TV', volume_level: 0.3, media_title: 'News' } },
  { entity_id: 'lock.front_door', state: 'locked', attributes: { friendly_name: 'Front door' } },
  { entity_id: 'switch.speaker_loudness', state: 'on', attributes: { friendly_name: 'Speaker Loudness' } },
  { entity_id: 'sensor.sun_next_setting', state: '2026-11-11T00:52:58+00:00', attributes: {} },
  { entity_id: 'weather.home', state: 'sunny', attributes: { temperature: 61, temperature_unit: '°F' } },
]

/** A reader whose fetch answers /api/states with STATES and records service calls. */
function readerWith(changed: unknown[] = [{ entity_id: 'x' }]) {
  const fetch = vi.fn(async (url: string, _init?: RequestInit) => {
    if (url.endsWith('/api/states')) return Response.json(STATES)
    // Home Assistant's template answer: the speaker's own settings switch.
    if (url.endsWith('/api/template')) return new Response('["switch.speaker_loudness"]')
    return Response.json(changed)
  })
  return { reader: createHomeReader(config, { fetch }), fetch }
}

describe('home reader', () => {
  it("shows lights and media, not locks or a speaker's settings, with brightness and volume as 0-1", async () => {
    const home: any = await readerWith().reader.read()
    expect(home.devices.map((d: { id: string }) => d.id)).toEqual(['light.lamp', 'media_player.tv'])
    expect(home.devices[0].brightness).toBe(0.6)
    expect(home.devices[1]).toMatchObject({ volume: 0.3, detail: 'News' })
    expect(home.weather).toEqual({ condition: 'sunny', temperature: 61, unit: '°F' })
    expect(home.sun.setting).toBe('2026-11-11T00:52:58+00:00')
  })

  it('is null without a token', async () => {
    expect(await createHomeReader(loadConfig({ HA_TOKEN: '' })).read()).toBeNull()
  })

  it('turns page commands into the one matching service call', async () => {
    const { reader, fetch } = readerWith()
    await reader.act('light.lamp', 'brightness', 0.4)
    let [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toBe('http://192.168.68.94:8123/api/services/light/turn_on')
    expect(JSON.parse(String(init!.body))).toEqual({ entity_id: 'light.lamp', brightness_pct: 40 })

    await reader.act('media_player.tv', 'power', undefined, 'off')
    ;[url] = fetch.mock.calls.at(-1)!
    expect(url).toMatch(/media_player\/turn_on$/)
    await reader.act('media_player.tv', 'power', undefined, 'playing')
    ;[url] = fetch.mock.calls.at(-1)!
    expect(url).toMatch(/media_player\/turn_off$/)
  })

  it('refuses locks, unknown commands, bad ids and bad values without calling Home Assistant', async () => {
    const { reader, fetch } = readerWith()
    expect((await reader.act('lock.front_door', 'toggle')).ok).toBe(false)
    expect((await reader.act('light.lamp', 'unlock')).ok).toBe(false)
    expect((await reader.act('light.lamp; rm', 'toggle')).ok).toBe(false)
    expect((await reader.act('light.lamp', 'brightness', 7)).ok).toBe(false)
    expect(fetch).not.toHaveBeenCalled()
  })

  it("says so when on/off went through but the device didn't change", async () => {
    const asleep = readerWith([])
    const result = await asleep.reader.act('media_player.tv', 'power', undefined, 'off')
    expect(result.ok).toBe(false)
    expect(result.message).toMatch(/didn’t respond/)
    // Volume it already has changes nothing either, and that's not a failure.
    expect((await asleep.reader.act('media_player.tv', 'volume', 0.3)).ok).toBe(true)
    expect((await readerWith().reader.act('light.lamp', 'toggle')).ok).toBe(true)
  })

  it('reads a thermostat: room and target temperature, limits, step and the modes it offers', () => {
    const d = toDevice({
      entity_id: 'climate.thermostat', state: 'heat',
      attributes: { friendly_name: 'Thermostat', current_temperature: 68, temperature: 70, min_temp: 50, max_temp: 90, hvac_modes: ['off', 'heat', 'cool', 'weird'], hvac_action: 'heating' },
    })
    expect(d).toEqual({
      id: 'climate.thermostat', name: 'Thermostat', kind: 'climate', state: 'heat', available: true,
      current: 68, target: 70, min: 50, max: 90, step: 1, modes: ['off', 'heat', 'cool'], detail: 'heating',
    })
    // In Heat/Cool HA gives a range instead of one target: no target, not 0.
    const range: any = toDevice({ entity_id: 'climate.t', state: 'heat_cool', attributes: { current_temperature: 68, temperature: null } })
    expect(range.target).toBeUndefined()
  })

  it('sets a thermostat temperature and mode, and refuses anything else', async () => {
    const { reader, fetch } = readerWith()
    await reader.act('climate.thermostat', 'target', 71)
    let [url, init] = fetch.mock.calls.at(-1)!
    expect(url).toMatch(/climate\/set_temperature$/)
    expect(JSON.parse(String(init!.body))).toEqual({ entity_id: 'climate.thermostat', temperature: 71 })
    await reader.act('climate.thermostat', 'mode', 'cool')
    ;[url, init] = fetch.mock.calls.at(-1)!
    expect(url).toMatch(/climate\/set_hvac_mode$/)
    expect(JSON.parse(String(init!.body))).toEqual({ entity_id: 'climate.thermostat', hvac_mode: 'cool' })
    const calls = fetch.mock.calls.length
    expect((await reader.act('climate.thermostat', 'target', '71')).ok).toBe(false)
    expect((await reader.act('climate.thermostat', 'target', 500)).ok).toBe(false)
    expect((await reader.act('climate.thermostat', 'mode', 'emergency_heat')).ok).toBe(false)
    expect((await reader.act('climate.thermostat', 'toggle')).ok).toBe(false)
    expect((await reader.act('light.lamp', 'target', 70)).ok).toBe(false)
    expect(fetch.mock.calls.length).toBe(calls)
  })

  it('leaves out anything that is not a device', () => {
    expect(toDevice({ entity_id: 'sensor.x', state: '1', attributes: {} })).toBeNull()
  })
})

describe('live control', () => {
  it('needs a Tailscale login, like Ask Jarvis', async () => {
    const fetch = vi.fn(async () => Response.json(STATES))
    const source = createLiveSource(config, { fetch, execFile: vi.fn(), statfs: vi.fn() })
    const result = await source.control('light.lamp', 'toggle', undefined, {})
    expect(result).toEqual({ ok: false, message: 'Open this page through Tailscale to control the house' })
    expect(fetch).not.toHaveBeenCalled()
  })
})
