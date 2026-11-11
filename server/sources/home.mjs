// Home Assistant, for the Home page: the devices worth a button, the
// weather and the sun, and a short list of commands the page may send.
//
// The page never names a Home Assistant service. It sends a command from
// COMMANDS for one entity, and this file turns that into the one service
// call it stands for, for the kinds of device in KINDS only. Locks, alarms
// and garage doors are left out on purpose.

const TIMEOUT_MS = 2500
const ENTITY = /^[a-z_]+\.[a-z0-9_]+$/

/** The domains shown on the page, and what each is called there. */
const KINDS = {
  light: 'light',
  switch: 'switch',
  fan: 'fan',
  input_boolean: 'switch',
  media_player: 'media',
  scene: 'scene',
  script: 'script',
  climate: 'climate',
}

/** Page command -> Home Assistant service, per kind. */
const COMMANDS = {
  light: { toggle: 'toggle', brightness: 'turn_on' },
  switch: { toggle: 'toggle' },
  fan: { toggle: 'toggle' },
  media: { power: null, playpause: 'media_play_pause', volume: 'volume_set' },
  scene: { run: 'turn_on' },
  script: { run: 'turn_on' },
  climate: { target: 'set_temperature', mode: 'set_hvac_mode' },
}

/** The thermostat modes the page may pick, as Home Assistant names them. */
const HVAC_MODES = ['off', 'heat', 'cool', 'heat_cool', 'auto', 'dry', 'fan_only']
// A target outside this (degrees, F or C) is a typo, not a setting.
const TEMP_RANGE = [0, 100]

// Switches that belong to a speaker or TV (a Sonos's "Loudness" or
// "Crossfade") are its settings, not things in the house. The states API
// doesn't say which device an entity is on, so a template asks.
const SETTINGS_TEMPLATE = "{% set ns = namespace(out=[]) %}{% for s in states.switch %}{% set d = device_id(s.entity_id) %}" +
  "{% if d and device_entities(d) | select('match', 'media_player[.]') | list | count > 0 %}{% set ns.out = ns.out + [s.entity_id] %}{% endif %}" +
  '{% endfor %}{{ ns.out | tojson }}'

/** Rounds a 0-1 share to two places. */
const share = (n) => Math.round(n * 100) / 100

/** One Home Assistant state as a device on the page, or null to leave it out. */
export function toDevice(entity) {
  const domain = entity.entity_id.split('.')[0]
  const kind = KINDS[domain]
  if (!kind) return null
  const a = entity.attributes ?? {}
  const device = {
    id: entity.entity_id,
    name: a.friendly_name ?? entity.entity_id,
    kind,
    state: entity.state,
    available: entity.state !== 'unavailable' && entity.state !== 'unknown',
  }
  if (kind === 'light' && typeof a.brightness === 'number') device.brightness = share(a.brightness / 255)
  if (kind === 'media') {
    if (typeof a.volume_level === 'number') device.volume = share(a.volume_level)
    const playing = [a.media_artist, a.media_title].filter(Boolean).join(' · ')
    if (playing) device.detail = playing
    else if (a.app_name) device.detail = a.app_name
  }
  if (kind === 'climate') Object.assign(device, climateFields(a))
  return device
}

/** A number, or undefined when Home Assistant didn't give one. */
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined)

/** A thermostat's temperatures, limits and modes, from its attributes. */
function climateFields(a) {
  const fields = {
    current: num(a.current_temperature),
    target: num(a.temperature),
    min: num(a.min_temp),
    max: num(a.max_temp),
    step: num(a.target_temp_step) ?? 1,
    modes: Array.isArray(a.hvac_modes) ? a.hvac_modes.filter((m) => HVAC_MODES.includes(m)) : [],
  }
  if (typeof a.hvac_action === 'string') fields.detail = a.hvac_action
  // Leave out what's missing, so the page can tell "not reported" from 0.
  for (const k of Object.keys(fields)) if (fields[k] === undefined) delete fields[k]
  return fields
}

/** Creates the reader. `deps.fetch` is swappable for tests. */
// What the page says when HA took a power command but nothing switched.
const NO_RESPONSE = 'Home Assistant sent it, but the device didn’t respond. It may be asleep or disconnected from Home Assistant.'

/**
 * HA answers a service call with the states it changed. An empty list after
 * on/off means the device ignored it, which HA itself doesn't report as an
 * error (an Apple TV that has lost its connection, for one). Only on/off is
 * checked: setting a volume it already has also changes nothing, and that's fine.
 */
async function nothingChanged(res) {
  try {
    const changed = await res.json()
    return Array.isArray(changed) && changed.length === 0
  } catch {
    return false
  }
}

export function createHomeReader(config, deps = {}) {
  const fetchFn = deps.fetch ?? globalThis.fetch
  const headers = { Authorization: `Bearer ${config.haToken}`, 'content-type': 'application/json' }

  /** Entity ids of switches that are a speaker's or TV's settings; none if the template fails. */
  async function settingsSwitches() {
    try {
      const res = await fetchFn(`${config.haUrl}/api/template`, {
        method: 'POST', headers, body: JSON.stringify({ template: SETTINGS_TEMPLATE }), signal: AbortSignal.timeout(TIMEOUT_MS),
      })
      if (!res.ok) return new Set()
      return new Set(JSON.parse(await res.text()))
    } catch {
      return new Set()
    }
  }

  return {
    /** Devices, weather and sun times, or null without a token or when HA is down. */
    async read() {
      if (!config.haToken) return null
      try {
        const [res, hidden] = await Promise.all([
          fetchFn(`${config.haUrl}/api/states`, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) }),
          settingsSwitches(),
        ])
        if (!res.ok) return null
        const states = await res.json()
        const devices = []
        let weather = null
        const sun = { rising: null, setting: null }
        for (const e of states) {
          const device = toDevice(e)
          if (device && !hidden.has(device.id)) devices.push(device)
          if (weather === null && e.entity_id.startsWith('weather.')) {
            weather = { condition: e.state, temperature: e.attributes?.temperature ?? null, unit: e.attributes?.temperature_unit ?? '' }
          }
          if (e.entity_id === 'sensor.sun_next_rising') sun.rising = e.state
          if (e.entity_id === 'sensor.sun_next_setting') sun.setting = e.state
        }
        // The thermostat first, then things you can switch, media, scenes and scripts; A-Z within.
        const order = ['climate', 'light', 'switch', 'fan', 'media', 'scene', 'script']
        devices.sort((x, y) => order.indexOf(x.kind) - order.indexOf(y.kind) || x.name.localeCompare(y.name))
        return { devices, weather, sun }
      } catch {
        return null
      }
    },

    /**
     * Sends one command to one entity. `value` is 0-1 for brightness and
     * volume, degrees for a thermostat's target, a mode name for its mode. `current` is the device's state, needed to pick on or off for
     * a media player's power button.
     */
    async act(entityId, command, value, current) {
      if (!config.haToken) return { ok: false, message: 'Home Assistant has no token set' }
      if (!ENTITY.test(entityId)) return { ok: false, message: 'Not a device' }
      const domain = entityId.split('.')[0]
      const kind = KINDS[domain]
      if (!kind || !(command in COMMANDS[kind])) return { ok: false, message: `Can't ${command} that` }

      let service = COMMANDS[kind][command]
      const data = { entity_id: entityId }
      if (command === 'power') service = current === 'off' ? 'turn_on' : 'turn_off'
      if (command === 'brightness' || command === 'volume') {
        if (typeof value !== 'number' || !(value >= 0 && value <= 1)) return { ok: false, message: 'Send a value from 0 to 1' }
        if (command === 'brightness') data.brightness_pct = Math.round(value * 100)
        else data.volume_level = share(value)
      }
      if (command === 'target') {
        if (typeof value !== 'number' || !(value >= TEMP_RANGE[0] && value <= TEMP_RANGE[1])) return { ok: false, message: 'Send a temperature' }
        data.temperature = Math.round(value * 10) / 10
      }
      if (command === 'mode') {
        if (!HVAC_MODES.includes(value)) return { ok: false, message: 'Not a thermostat mode' }
        data.hvac_mode = value
      }

      try {
        const res = await fetchFn(`${config.haUrl}/api/services/${domain}/${service}`, {
          method: 'POST', headers, body: JSON.stringify(data), signal: AbortSignal.timeout(10_000),
        })
        if (!res.ok) return { ok: false, message: `Home Assistant answered ${res.status}` }
        if (command === 'power' || command === 'toggle') {
          if (await nothingChanged(res)) return { ok: false, message: NO_RESPONSE }
        }
        return { ok: true, message: 'Done' }
      } catch {
        return { ok: false, message: 'Home Assistant is not answering' }
      }
    },
  }
}
