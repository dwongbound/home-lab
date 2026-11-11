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

/** One device: its state and the controls for its kind. */
function DeviceTile({ device }: { device: Device }) {
  const { mutate } = useSWRConfig()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const off = !device.available || busy
  const isOn = device.state === 'on'

  /** Sends one command, then refetches so every tile shows the house as it is. */
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

  let controls: React.ReactNode = null
  if (device.kind === 'light' || device.kind === 'switch' || device.kind === 'fan') {
    controls = (
      <>
        <button type="button" className={isOn ? 'btn btn--primary btn--wide' : 'btn btn--wide'} aria-pressed={isOn} disabled={off} onClick={() => send('toggle')}>
          {isOn ? 'Turn off' : 'Turn on'}
        </button>
        {device.kind === 'light' && device.brightness !== undefined ? (
          <Level label="Brightness" value={device.brightness} disabled={off} onCommit={(v) => send('brightness', v)} />
        ) : null}
      </>
    )
  } else if (device.kind === 'media') {
    const poweredOff = device.state === 'off' || !device.available
    controls = (
      <>
        <div className="device__row">
          <button type="button" className="btn" disabled={off} onClick={() => send('power')}>{poweredOff ? 'Turn on' : 'Turn off'}</button>
          {!poweredOff ? (
            <button type="button" className="btn btn--primary" disabled={off} onClick={() => send('playpause')}>
              {device.state === 'playing' ? 'Pause' : 'Play'}
            </button>
          ) : null}
        </div>
        {!poweredOff && device.volume !== undefined ? (
          <Level label="Volume" value={device.volume} disabled={off} onCommit={(v) => send('volume', v)} />
        ) : null}
      </>
    )
  } else if (device.kind === 'climate') {
    controls = (
      <>
        {device.current !== undefined ? (
          <p className="thermo__now"><span className="thermo__label">Inside</span>{device.current}°</p>
        ) : null}
        {device.state !== 'off' && device.target !== undefined ? (
          <Target device={device} disabled={off} onCommit={(v) => send('target', v)} />
        ) : null}
        {device.modes && device.modes.length > 0 ? (
          <div className="thermo__modes" role="group" aria-label="Mode">
            {device.modes.map((m) => (
              <button
                key={m} type="button" className={device.state === m ? 'btn btn--primary' : 'btn'}
                aria-pressed={device.state === m} disabled={off} onClick={() => send('mode', m)}
              >
                {MODE_WORDS[m] ?? m}
              </button>
            ))}
          </div>
        ) : null}
      </>
    )
  } else {
    controls = <button type="button" className="btn btn--wide" disabled={off} onClick={() => send('run')}>Run</button>
  }

  return (
    <section className="glass panel device" data-on={isOn || device.state === 'playing' || (device.kind === 'climate' && device.state !== 'off') || undefined} data-unavailable={!device.available || undefined} aria-label={device.name}>
      <header className="device__head">
        <h2 className="panel__title">{device.name}</h2>
        <p className="panel__sub">{stateText(device)}</p>
      </header>
      {controls}
      {busy ? <Spinner label="Working…" /> : null}
      {error ? <p className="device__error" role="alert">{error}</p> : null}
    </section>
  )
}

/** The Home page. */
export function Home({ data, now }: { data: Snapshot; now: Date }) {
  const home = data.home
  return (
    <>
      <section className="hero hero--small">
        <h1 className="hero__title">Home</h1>
        {home ? <p className="hero__sub">{weatherLine(home, now)}</p> : null}
      </section>
      {home === null ? (
        <section className="glass panel">
          <p className="empty">Home Assistant isn’t answering, or has no token set. The Services page says which.</p>
        </section>
      ) : home.devices.length === 0 ? (
        <section className="glass panel">
          <p className="empty">No thermostats, lights, switches, speakers or scenes in Home Assistant yet. Add them there and they’ll show up here.</p>
        </section>
      ) : (
        <div className="grid grid--devices">
          {home.devices.map((d) => <DeviceTile key={d.id} device={d} />)}
        </div>
      )}
    </>
  )
}
