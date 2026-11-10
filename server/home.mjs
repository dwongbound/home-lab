// Home Assistant, the parts both sources share: which entities the Home
// page shows, what each command is allowed to do, and which HA service a
// command becomes. The live source calls HA with the result; the mock source
// pretends. Keeping the rules here means the page can only ever ask HA for
// these few things, whatever a request says.

/** HA domains the page shows, and the kind of tile each one gets. */
const KIND_BY_DOMAIN = {
  light: 'light',
  switch: 'switch',
  input_boolean: 'switch',
  fan: 'fan',
  climate: 'climate',
  lock: 'lock',
  cover: 'cover',
  scene: 'scene',
}

/** The order tiles are listed in, so the page is the same every refresh. */
const KIND_ORDER = ['scene', 'light', 'climate', 'lock', 'cover', 'fan', 'switch']

/** Which commands each kind of device accepts. */
const COMMANDS_BY_KIND = {
  light: ['turn_on', 'turn_off', 'brightness'],
  switch: ['turn_on', 'turn_off'],
  fan: ['turn_on', 'turn_off'],
  climate: ['turn_on', 'turn_off', 'temperature'],
  lock: ['lock', 'unlock'],
  cover: ['open', 'close'],
  scene: ['activate'],
}

// An entity id is "<domain>.<object id>", lower case. Anything else is refused
// before it gets near HA.
const ENTITY_ID = /^([a-z_]+)\.[a-z0-9_]+$/

// Wide enough for both °F and °C thermostats.
const TEMPERATURE_RANGE = [5, 95]

/** The domain part of an entity id ("light" for "light.desk"), or null. */
function domainOf(id) {
  const match = ENTITY_ID.exec(id)
  if (match === null) return null
  return match[1]
}

/** The tile kind for an entity id, or null when the page doesn't show that domain. */
export function kindOf(id) {
  const domain = domainOf(id)
  if (domain === null) return null
  return KIND_BY_DOMAIN[domain] ?? null
}

/** Whether a light can dim: it has at least one colour mode besides plain on/off. */
function canDim(attributes) {
  const modes = attributes.supported_color_modes
  if (!Array.isArray(modes)) return false
  return modes.some((mode) => mode !== 'onoff')
}

/** "On" in the page's sense, which depends on the kind (see HomeDevice in src/types.ts). */
function isOn(kind, state) {
  if (kind === 'lock') return state === 'locked'
  if (kind === 'cover') return state === 'open' || state === 'opening'
  if (kind === 'climate') return state !== 'off' && state !== 'unavailable'
  if (kind === 'scene') return false
  return state === 'on'
}

/** A number from HA, or null when it's missing. */
function numberOrNull(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  return null
}

/** Turns one HA state object into a HomeDevice, or null if the page doesn't show it. */
function toDevice(entity) {
  const kind = kindOf(entity.entity_id)
  if (kind === null) return null
  const attributes = entity.attributes ?? {}
  const state = String(entity.state)
  const on = isOn(kind, state)

  // A scene that was never run reads "unknown", which is fine for a scene.
  let unavailable = state === 'unavailable'
  if (state === 'unknown' && kind !== 'scene') unavailable = true

  // HA reports brightness as 0-255 and only while the light is on.
  let brightness = null
  if (kind === 'light' && canDim(attributes)) {
    brightness = 0
    if (on && typeof attributes.brightness === 'number') brightness = Math.round((attributes.brightness / 255) * 100)
  }

  let temperature = null
  let target = null
  if (kind === 'climate') {
    temperature = numberOrNull(attributes.current_temperature)
    target = numberOrNull(attributes.temperature)
  }

  return {
    id: entity.entity_id,
    name: String(attributes.friendly_name ?? entity.entity_id),
    kind,
    on,
    state,
    unavailable,
    brightness,
    temperature,
    target,
  }
}

/** HA's /api/states list as the page's devices, grouped by kind then sorted by name. */
export function toDevices(states) {
  const devices = []
  for (const entity of states) {
    const device = toDevice(entity)
    if (device !== null) devices.push(device)
  }
  devices.sort((a, b) => {
    const byKind = KIND_ORDER.indexOf(a.kind) - KIND_ORDER.indexOf(b.kind)
    if (byKind !== 0) return byKind
    return a.name.localeCompare(b.name)
  })
  return devices
}

/**
 * Checks a request body from the page. Returns { request } when it's one of
 * the allowed commands for that kind of device, or { error } saying why not.
 */
export function parseHomeRequest(body) {
  const id = typeof body?.id === 'string' ? body.id : ''
  const command = typeof body?.command === 'string' ? body.command : ''
  const kind = kindOf(id)
  if (kind === null) return { error: `Not a device the page controls: ${id || '(none)'}` }
  if (!COMMANDS_BY_KIND[kind].includes(command)) return { error: `A ${kind} can't ${command || '(nothing)'}` }

  if (command === 'brightness') {
    const value = body.value
    if (typeof value !== 'number' || value < 1 || value > 100) return { error: 'Brightness is 1 to 100' }
    return { request: { id, command, value: Math.round(value) } }
  }
  if (command === 'temperature') {
    const value = body.value
    const [low, high] = TEMPERATURE_RANGE
    if (typeof value !== 'number' || value < low || value > high) return { error: `Temperature is ${low} to ${high}` }
    return { request: { id, command, value } }
  }
  return { request: { id, command } }
}

/**
 * The HA service call for a checked request: POST /api/services/<domain>/<service>
 * with `data` as the body.
 */
export function serviceCall(request) {
  const domain = domainOf(request.id)
  const data = { entity_id: request.id }
  if (request.command === 'brightness') {
    return { domain, service: 'turn_on', data: { ...data, brightness_pct: request.value } }
  }
  if (request.command === 'temperature') {
    return { domain, service: 'set_temperature', data: { ...data, temperature: request.value } }
  }
  if (request.command === 'open') return { domain, service: 'open_cover', data }
  if (request.command === 'close') return { domain, service: 'close_cover', data }
  if (request.command === 'activate') return { domain, service: 'turn_on', data }
  // turn_on, turn_off, lock and unlock are HA's own service names.
  return { domain, service: request.command, data }
}

/**
 * What a command did, in a few words ("unlocked"). The page puts the
 * device's name in front for its toast: "Front door unlocked".
 */
export function doneMessage(request) {
  const words = {
    turn_on: 'turned on',
    turn_off: 'turned off',
    brightness: `set to ${request.value}%`,
    temperature: `set to ${request.value}°`,
    lock: 'locked',
    unlock: 'unlocked',
    open: 'opening',
    close: 'closing',
    activate: 'started',
  }
  return words[request.command]
}
