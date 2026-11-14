// The Home page: the thermostat, every light, switch, fan, speaker, TV, scene and script in
// Home Assistant, each with the buttons that make sense for it, plus the
// weather and the sun. New devices show up here as they're added to Home
// Assistant; locks, alarms and garage doors are deliberately left out
// (server/sources/home.mjs).
import { useEffect, useRef, useState } from 'react'
import { useSWRConfig } from 'swr'
import type { Device, HomeCommand, HomeState, Snapshot } from '../types'
import { controlDevice, SNAPSHOT_KEY } from '../api/client'
import { clock } from '../lib/format'
import { Spinner } from '../components/Spinner'
import { Icon, type IconName } from '../components/Icon'

/** Home Assistant's weather words, as people say them. */
const WEATHER: Record<string, string> = {
  'clear-night': 'Clear', cloudy: 'Cloudy', fog: 'Foggy', hail: 'Hail', lightning: 'Thunderstorms',
  'lightning-rainy': 'Thunderstorms', partlycloudy: 'Partly cloudy', pouring: 'Pouring', rainy: 'Rainy',
  snowy: 'Snowy', 'snowy-rainy': 'Sleet', sunny: 'Sunny', windy: 'Windy', 'windy-variant': 'Windy',
}

/** The line under the title: weather and the next sunrise or sunset. */
function weatherLine(home: HomeState, now: Date): string {
  const parts: string[] = []
  const w = home.weather
  if (w) parts.push(w.temperature === null ? (WEATHER[w.condition] ?? w.condition) : `${WEATHER[w.condition] ?? w.condition}, ${Math.round(w.temperature)}${w.unit}`)
  const { rising, setting } = home.sun
  if (setting && rising) {
    const nextIsSunset = new Date(setting).getTime() - now.getTime() < new Date(rising).getTime() - now.getTime()
    parts.push(nextIsSunset ? `sunset ${clock(setting)}` : `sunrise ${clock(rising)}`)
  }
  return parts.length ? `${parts.join(' · ')}.` : ''
}

/** A thermostat's modes, as people say them. */
const MODE_WORDS: Record<string, string> = {
  off: 'Off', heat: 'Heat', cool: 'Cool', heat_cool: 'Heat/Cool', auto: 'Auto', dry: 'Dry', fan_only: 'Fan',
}

/** What a thermostat is doing, as people say it ("heating" → "Heating"). */
function climateText(d: Device): string {
  if (d.state === 'off') return 'Off'
  const doing = d.detail ? d.detail.charAt(0).toUpperCase() + d.detail.slice(1) : (MODE_WORDS[d.state] ?? d.state)
  return d.target === undefined ? doing : `${doing}, set to ${d.target}°`
}

/** A device's state in words. */
function stateText(d: Device): string {
  if (!d.available) return 'Unavailable'
  if (d.kind === 'climate') return climateText(d)
  if (d.kind === 'scene' || d.kind === 'script') return d.kind === 'scene' ? 'Scene' : 'Script'
  const word = { on: 'On', off: 'Off', playing: 'Playing', paused: 'Paused', idle: 'Idle', standby: 'Standby' }[d.state] ?? d.state
  return d.detail && d.state !== 'off' ? `${word} · ${d.detail}` : word
}

/**
 * A 0-1 slider that sends its value once you stop moving it (so dragging
 * doesn't fire a command per pixel), and follows the house otherwise.
 */
function Level({ label, value, disabled, onCommit }: { label: string; value: number; disabled: boolean; onCommit: (v: number) => void }) {
  const [local, setLocal] = useState(value)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => { setLocal(value) }, [value])
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])
  return (
    <label className="device__level">
      <span>{label}</span>
      <input
        type="range" min={0} max={100} step={1} value={Math.round(local * 100)} disabled={disabled}
        onChange={(e) => {
          const v = Number(e.target.value) / 100
          setLocal(v)
          if (timer.current) clearTimeout(timer.current)
          timer.current = setTimeout(() => onCommit(v), 350)
        }}
      />
      <span className="device__pct">{Math.round(local * 100)}%</span>
    </label>
  )
}

/**
 * A thermostat's target with − and + buttons. Presses add up on screen
 * and send once you stop pressing, so three taps is one command, not three.
 */
function Target({ device, disabled, onCommit }: { device: Device; disabled: boolean; onCommit: (v: number) => void }) {
  const target = device.target ?? 0
  const step = device.step ?? 1
  const [local, setLocal] = useState(target)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => { setLocal(target) }, [target])
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current) }, [])

  /** Moves the target one step up or down, within the thermostat's limits. */
  function nudge(by: number) {
    let next = Math.round((local + by * step) * 10) / 10
    if (device.min !== undefined) next = Math.max(device.min, next)
    if (device.max !== undefined) next = Math.min(device.max, next)
    setLocal(next)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => onCommit(next), 700)
  }

  const atMin = device.min !== undefined && local <= device.min
  const atMax = device.max !== undefined && local >= device.max
  return (
    <div className="thermo__set">
      <button type="button" className="btn thermo__step" aria-label="Cooler" disabled={disabled || atMin} onClick={() => nudge(-1)}>−</button>
      <p className="thermo__target" aria-live="polite"><span className="thermo__label">Set to</span>{local}°</p>
      <button type="button" className="btn thermo__step" aria-label="Warmer" disabled={disabled || atMax} onClick={() => nudge(1)}>+</button>
    </div>
  )
}

/** Sends commands for one device and refetches, so every tile shows the house as it is. */
function useDeviceControl(device: Device) {
  const { mutate } = useSWRConfig()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  /** Sends one command, then refetches the snapshot. */
  async function send(command: HomeCommand, value?: number | string) {
    setBusy(true)
    setError(null)
    try {
      const result = await controlDevice(device.id, command, value)
      if (!result.ok) setError(result.message)
      await mutate(SNAPSHOT_KEY)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'The request failed')
    } finally {
      setBusy(false)
    }
  }
  return { busy, error, send }
}

/** Whether a device counts as on, for the lit look. */
function isLit(d: Device): boolean {
  if (d.kind === 'climate') return d.state !== 'off'
  return d.state === 'on' || d.state === 'playing'
}

/** The icon for a device: a moon for a sleep switch ("Dylan asleep"), else by kind. */
function deviceIcon(d: Device): IconName {
  if (/sleep|asleep/i.test(d.name)) return 'moon'
  if (d.kind === 'light') return 'bulb'
  if (d.kind === 'fan') return 'fan'
  if (d.kind === 'media') return /tv/i.test(d.name) ? 'tv' : 'speaker'
  if (d.kind === 'scene' || d.kind === 'script') return 'sparkle'
  return 'toggle'
}

/**
 * The thermostat, first and widest: the room's temperature, the target
 * with − and +, and the modes as one segmented control.
 */
function Thermostat({ device }: { device: Device }) {
  const { busy, error, send } = useDeviceControl(device)
  const off = !device.available || busy
  return (
    <section className="glass panel thermo" data-on={isLit(device) || undefined} aria-label={device.name}>
      <header className="thermo__head">
        <h2 className="panel__title">{device.name}</h2>
        <p className="panel__sub">{stateText(device)}</p>
      </header>
      <div className="thermo__body">
        {device.current !== undefined ? (
          <p className="thermo__now"><span className="thermo__label">Inside</span>{device.current}°</p>
        ) : null}
        {device.state !== 'off' && device.target !== undefined ? (
          <Target device={device} disabled={off} onCommit={(v) => send('target', v)} />
        ) : null}
      </div>
      {device.modes && device.modes.length > 0 ? (
        <div className="seg" role="group" aria-label="Mode">
          {device.modes.map((m) => (
            <button key={m} type="button" className="seg__btn" aria-pressed={device.state === m} disabled={off} onClick={() => send('mode', m)}>
              {MODE_WORDS[m] ?? m}
            </button>
          ))}
        </div>
      ) : null}
      {busy ? <Spinner label="Working…" /> : null}
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </section>
  )
}

/**
 * A light, switch or fan: the whole tile is the switch (tap to turn it on
 * or off), lit when on. A light that's on also gets its brightness.
 */
function ToggleTile({ device }: { device: Device }) {
  const { busy, error, send } = useDeviceControl(device)
  const on = device.state === 'on'
  return (
    <li className="tile" data-on={on || undefined} aria-label={device.name} role="group">
      <button type="button" className="tile__hit" aria-pressed={on} aria-label={`${on ? 'Turn off' : 'Turn on'} ${device.name}`} disabled={busy} onClick={() => send('toggle')}>
        <span className="tile__icon"><Icon name={deviceIcon(device)} size={20} /></span>
        <span className="tile__name">{device.name}</span>
        <span className="tile__state">{busy ? 'Working…' : stateText(device)}</span>
      </button>
      {on && device.kind === 'light' && device.brightness !== undefined ? (
        <Level label="Brightness" value={device.brightness} disabled={busy} onCommit={(v) => send('brightness', v)} />
      ) : null}
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </li>
  )
}

/** A speaker or TV: what's playing, play/pause and power, and the volume while it's on. */
function MediaTile({ device }: { device: Device }) {
  const { busy, error, send } = useDeviceControl(device)
  const poweredOff = device.state === 'off'
  const playing = device.state === 'playing'
  return (
    <li className="tile tile--media" data-on={isLit(device) || undefined} aria-label={device.name} role="group">
      <div className="tile__top">
        <span className="tile__icon"><Icon name={deviceIcon(device)} size={20} /></span>
        <span className="tile__text">
          <span className="tile__name">{device.name}</span>
          <span className="tile__state">{busy ? 'Working…' : stateText(device)}</span>
        </span>
        <span className="tile__actions">
          {!poweredOff ? (
            <button type="button" className="round round--primary" aria-label={playing ? `Pause ${device.name}` : `Play ${device.name}`} disabled={busy} onClick={() => send('playpause')}>
              <Icon name={playing ? 'pause' : 'play'} size={18} />
            </button>
          ) : null}
          <button type="button" className="round" aria-label={poweredOff ? `Turn on ${device.name}` : `Turn off ${device.name}`} disabled={busy} onClick={() => send('power')}>
            <Icon name="power" size={18} />
          </button>
        </span>
      </div>
      {!poweredOff && device.volume !== undefined ? (
        <Level label="Volume" value={device.volume} disabled={busy} onCommit={(v) => send('volume', v)} />
      ) : null}
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </li>
  )
}

/** A scene or script: one chip that runs it. */
function SceneChip({ device }: { device: Device }) {
  const { busy, error, send } = useDeviceControl(device)
  return (
    <li>
      <button type="button" className="scene" aria-label={`Run ${device.name}`} disabled={busy} onClick={() => send('run')}>
        <Icon name="sparkle" size={16} />
        <span>{busy ? 'Running…' : device.name}</span>
      </button>
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </li>
  )
}

/** The Home page: thermostat, then switches and lights, media, scenes, and what's unreachable tucked away. */
export function Home({ data, now }: { data: Snapshot; now: Date }) {
  const home = data.home
  if (home === null) {
    return (
      <>
        <HomeHero />
        <section className="glass panel">
          <p className="empty">Home Assistant isn’t answering, or has no token set. The Services page says which.</p>
        </section>
      </>
    )
  }
  const live = home.devices.filter((d) => d.available)
  const unreachable = home.devices.filter((d) => !d.available)
  const thermostats = live.filter((d) => d.kind === 'climate')
  const toggles = live.filter((d) => d.kind === 'light' || d.kind === 'switch' || d.kind === 'fan')
  const media = live.filter((d) => d.kind === 'media')
  const scenes = live.filter((d) => d.kind === 'scene' || d.kind === 'script')
  return (
    <>
      <HomeHero line={weatherLine(home, now)} />
      {home.devices.length === 0 ? (
        <section className="glass panel">
          <p className="empty">No thermostats, lights, switches, speakers or scenes in Home Assistant yet. Add them there and they’ll show up here.</p>
        </section>
      ) : null}
      <div className="home">
        {thermostats.map((d) => <Thermostat key={d.id} device={d} />)}
        {toggles.length > 0 ? (
          <section className="glass panel home__group" aria-label="Lights and switches">
            <h2 className="home__label">Lights and switches</h2>
            <ul className="tiles">{toggles.map((d) => <ToggleTile key={d.id} device={d} />)}</ul>
          </section>
        ) : null}
        {media.length > 0 ? (
          <section className="glass panel home__group" aria-label="Speakers and TVs">
            <h2 className="home__label">Speakers and TVs</h2>
            <ul className="tiles tiles--media">{media.map((d) => <MediaTile key={d.id} device={d} />)}</ul>
          </section>
        ) : null}
        {scenes.length > 0 ? (
          <section className="glass panel home__group" aria-label="Scenes">
            <h2 className="home__label">Scenes</h2>
            <ul className="scenes">{scenes.map((d) => <SceneChip key={d.id} device={d} />)}</ul>
          </section>
        ) : null}
        {unreachable.length > 0 ? (
          <details className="glass panel home__away">
            <summary>{unreachable.length === 1 ? '1 device isn’t reachable' : `${unreachable.length} devices aren’t reachable`}</summary>
            <ul>{unreachable.map((d) => <li key={d.id}>{d.name}</li>)}</ul>
          </details>
        ) : null}
      </div>
    </>
  )
}

/** The page title and the weather line under it. */
function HomeHero({ line = '' }: { line?: string }) {
  return (
    <section className="hero hero--small">
      <h1 className="hero__title">Home</h1>
      {line ? <p className="hero__sub">{line}</p> : null}
    </section>
  )
}
