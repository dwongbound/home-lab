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
}

/** Page command -> Home Assistant service, per kind. */
const COMMANDS = {
  light: { toggle: 'toggle', brightness: 'turn_on' },
  switch: { toggle: 'toggle' },
  fan: { toggle: 'toggle' },
  media: { power: null, playpause: 'media_play_pause', volume: 'volume_set' },
  scene: { run: 'turn_on' },
  script: { run: 'turn_on' },
}

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
  return device
}

/** Creates the reader. `deps.fetch` is swappable for tests. */
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
        // Things you can switch first, then media, then scenes and scripts; A-Z within.
        const order = ['light', 'switch', 'fan', 'media', 'scene', 'script']
        devices.sort((x, y) => order.indexOf(x.kind) - order.indexOf(y.kind) || x.name.localeCompare(y.name))
        return { devices, weather, sun }
      } catch {
        return null
      }
    },

    /**
     * Sends one command to one entity. `value` is 0-1 for brightness and
     * volume. `current` is the device's state, needed to pick on or off for
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

      try {
        const res = await fetchFn(`${config.haUrl}/api/services/${domain}/${service}`, {
          method: 'POST', headers, body: JSON.stringify(data), signal: AbortSignal.timeout(10_000),
        })
        if (!res.ok) return { ok: false, message: `Home Assistant answered ${res.status}` }
        return { ok: true, message: 'Done' }
      } catch {
        return { ok: false, message: 'Home Assistant is not answering' }
      }
    },
  }
}
