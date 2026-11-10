import { memo, useState } from 'react'
import type { HomeCommand, HomeDevice, HomeRequest } from '../types'
import { Icon, type IconName } from './Icon'
import { Spinner } from './Spinner'

// The Home page's pieces: one tile per Home Assistant device, grouped into
// glass panels, and the scenes row. Tiles aren't glass themselves (one frosted
// panel holds many tiles), which keeps the page light on jarvis.
//
// A tile never changes its own state. It asks (onSend), shows a blocking
// spinner on itself while HA works, and then shows whatever the next snapshot
// says, so the page can't drift from the real house.

const ICON: Record<HomeDevice['kind'], IconName> = {
  light: 'bulb', switch: 'plug', fan: 'fan', climate: 'thermo', lock: 'lock', cover: 'garage', media: 'speaker', scene: 'sparkle',
}

/** The label on a tile's spinner while a command runs. */
export const BUSY_LABEL: Record<HomeCommand, string> = {
  turn_on: 'Turning on…',
  turn_off: 'Turning off…',
  brightness: 'Dimming…',
  temperature: 'Setting…',
  lock: 'Locking…',
  unlock: 'Unlocking…',
  open: 'Opening…',
  close: 'Closing…',
  play_pause: 'Sending…',
  volume: 'Setting volume…',
  activate: 'Starting…',
}

/** What a tile says under the device's name. */
function stateText(device: HomeDevice): string {
  if (device.unavailable) return 'Not responding'
  if (device.kind === 'lock') return device.on ? 'Locked' : 'Unlocked'
  if (device.kind === 'cover') return device.on ? 'Open' : 'Closed'
  if (device.kind === 'climate') {
    if (!device.on) return 'Off'
    let text = `${capitalize(device.state)}`
    if (device.target !== null) text += ` to ${device.target}°`
    return text
  }
  if (device.kind === 'media') {
    if (!device.on) return 'Off'
    if (device.state === 'on') return 'On'
    return capitalize(device.state)
  }
  if (!device.on) return 'Off'
  if (device.brightness !== null) return `On, ${device.brightness}%`
  return 'On'
}

/** "heat" → "Heat". */
function capitalize(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1)
}

/**
 * The command a tile's main button sends: the opposite of what the device
 * is now. Locks and covers have their own words for it.
 */
export function toggleCommand(device: HomeDevice): HomeCommand {
  if (device.kind === 'lock') return device.on ? 'unlock' : 'lock'
  if (device.kind === 'cover') return device.on ? 'close' : 'open'
  return device.on ? 'turn_off' : 'turn_on'
}

/** The main button's accessible name, which says what pressing it will do. */
function actionName(device: HomeDevice): string {
  const command = toggleCommand(device)
  if (command === 'unlock') return `Unlock ${device.name}`
  if (command === 'lock') return `Lock ${device.name}`
  if (command === 'open') return `Open ${device.name}`
  if (command === 'close') return `Close ${device.name}`
  return device.name
}

interface TileProps {
  device: HomeDevice
  /** The spinner label while a command for this device runs, else null. */
  busy: string | null
  onSend: (device: HomeDevice, request: HomeRequest) => void
}

/**
 * A level slider (a light's brightness, a speaker's volume) that only tells
 * HA when you let go, not on every step.
 */
function LevelSlider({ device, command, level, label, min, onSend }: {
  device: HomeDevice
  command: 'brightness' | 'volume'
  level: number
  label: string
  min: number
  onSend: TileProps['onSend']
}) {
  // While dragging, the slider shows where your finger is, not the snapshot.
  const [dragging, setDragging] = useState<number | null>(null)
  const shown = dragging ?? Math.max(min, level)

  /** Sends the value you let go at, if it changed. */
  function commit() {
    if (dragging === null) return
    if (dragging !== level) onSend(device, { id: device.id, command, value: dragging })
    setDragging(null)
  }

  return (
    <input
      type="range"
      className="device__range"
      min={min}
      max={100}
      value={shown}
      aria-label={label}
      disabled={device.unavailable}
      onChange={(e) => setDragging(Number(e.target.value))}
      onPointerUp={commit}
      onKeyUp={commit}
      onBlur={commit}
    />
  )
}

/** Play/pause and volume for a TV or speaker that's on. */
function MediaControls({ device, onSend }: { device: HomeDevice; onSend: TileProps['onSend'] }) {
  if (!device.on) return null
  const playing = device.state === 'playing'
  return (
    <div className="device__media">
      <button type="button" className="icon-btn device__step" aria-label={`${playing ? 'Pause' : 'Play'} ${device.name}`} onClick={() => onSend(device, { id: device.id, command: 'play_pause' })} disabled={device.unavailable}>
        <Icon name={playing ? 'pause' : 'play'} size={18} />
      </button>
      {device.volume !== null ? <LevelSlider device={device} command="volume" level={device.volume} label={`${device.name} volume`} min={0} onSend={onSend} /> : null}
    </div>
  )
}

/** − and + for a thermostat's set point, one degree a press. */
function TemperatureSteps({ device, onSend }: { device: HomeDevice; onSend: TileProps['onSend'] }) {
  if (device.target === null) return null
  const target = device.target
  /** Moves the set point by `step` degrees. */
  const nudge = (step: number) => onSend(device, { id: device.id, command: 'temperature', value: target + step })
  return (
    <div className="device__steps">
      <button type="button" className="icon-btn device__step" aria-label={`Lower ${device.name}`} onClick={() => nudge(-1)} disabled={device.unavailable}>−</button>
      <span className="device__target">{device.temperature !== null ? `${device.temperature}° now` : `Set ${target}°`}</span>
      <button type="button" className="icon-btn device__step" aria-label={`Raise ${device.name}`} onClick={() => nudge(1)} disabled={device.unavailable}>+</button>
    </div>
  )
}

/** One device. memo'd because the page re-renders on every 15 s refresh. */
export const DeviceTile = memo(function DeviceTile({ device, busy, onSend }: TileProps) {
  return (
    <li className="device" data-kind={device.kind} data-on={device.on ? '' : undefined} data-unavailable={device.unavailable ? '' : undefined} aria-busy={busy !== null}>
      <button
        type="button"
        className="device__main"
        aria-label={actionName(device)}
        aria-pressed={device.kind === 'lock' || device.kind === 'cover' ? undefined : device.on}
        disabled={device.unavailable || busy !== null}
        onClick={() => onSend(device, { id: device.id, command: toggleCommand(device) })}
      >
        <span className="device__icon"><Icon name={ICON[device.kind]} size={20} /></span>
        <span className="device__text">
          <span className="device__name">{device.name}</span>
          <span className="device__state">{stateText(device)}</span>
        </span>
      </button>
      {device.kind === 'light' && device.brightness !== null ? (
        <LevelSlider device={device} command="brightness" level={device.brightness} label={`${device.name} brightness`} min={1} onSend={onSend} />
      ) : null}
      {device.kind === 'media' ? <MediaControls device={device} onSend={onSend} /> : null}
      {device.kind === 'climate' ? <TemperatureSteps device={device} onSend={onSend} /> : null}
      {busy !== null ? <div className="device__block"><Spinner label={busy} /></div> : null}
    </li>
  )
})

/** A titled glass panel of device tiles. Renders nothing when the group is empty. */
export function DeviceGroup({ title, devices, busy, onSend }: { title: string; devices: HomeDevice[]; busy: Record<string, string>; onSend: TileProps['onSend'] }) {
  if (devices.length === 0) return null
  const id = `home-${title.toLowerCase().replace(/\W+/g, '-')}`
  return (
    <section className="glass panel" aria-labelledby={id}>
      <header className="panel__head"><h2 id={id} className="panel__title">{title}</h2></header>
      <ul className="devices">
        {devices.map((d) => <DeviceTile key={d.id} device={d} busy={busy[d.id] ?? null} onSend={onSend} />)}
      </ul>
    </section>
  )
}

/** Scenes as a row of buttons; pressing one runs it. */
export function SceneRow({ scenes, busy, onSend }: { scenes: HomeDevice[]; busy: Record<string, string>; onSend: TileProps['onSend'] }) {
  if (scenes.length === 0) return null
  return (
    <section className="glass panel" aria-labelledby="home-scenes">
      <header className="panel__head"><h2 id="home-scenes" className="panel__title">Scenes</h2></header>
      <div className="scenes">
        {scenes.map((s) => (
          <button key={s.id} type="button" className="btn scenes__btn" disabled={s.unavailable || busy[s.id] !== undefined} onClick={() => onSend(s, { id: s.id, command: 'activate' })}>
            <Icon name="sparkle" size={16} />
            {busy[s.id] ?? s.name}
          </button>
        ))}
      </div>
    </section>
  )
}
