/**
 * Whether the thermostat is working right now (heating or cooling toward
 * the set temperature) or just holding. Home Assistant says so when the
 * thermostat reports it (`hvac_action`); the Amazon one doesn't, so then we
 * work it out from the mode and the room versus the set temperature.
 */
import type { Device } from '../types'

export type ThermoActivity = 'heating' | 'cooling' | 'idle' | 'off'

/** What the thermostat is doing, from what it reports or else from the temperatures. */
export function thermoActivity(d: Device): ThermoActivity {
  if (d.state === 'off') return 'off'
  const reported = reportedActivity(d.detail)
  if (reported) return reported
  if (d.current === undefined || d.target === undefined) return 'idle'
  const wantsHeat = d.state === 'heat' || d.state === 'heat_cool' || d.state === 'auto'
  const wantsCool = d.state === 'cool' || d.state === 'heat_cool' || d.state === 'auto'
  if (wantsHeat && d.current < d.target) return 'heating'
  if (wantsCool && d.current > d.target) return 'cooling'
  return 'idle'
}

/** Home Assistant's own word for it, when the thermostat reports one. */
function reportedActivity(action: string | undefined): ThermoActivity | null {
  if (action === 'heating' || action === 'preheating') return 'heating'
  if (action === 'cooling') return 'cooling'
  if (action === 'idle' || action === 'fan' || action === 'drying') return 'idle'
  if (action === 'off') return 'off'
  return null
}

/** The status line under the thermostat's name: "Cooling to 72°", "Holding at 72°". */
export function thermoStatus(d: Device): string {
  const activity = thermoActivity(d)
  if (activity === 'off') return 'Off'
  if (d.target === undefined) return activity === 'idle' ? 'Idle' : capital(activity)
  if (activity === 'heating') return `Heating to ${d.target}°`
  if (activity === 'cooling') return `Cooling to ${d.target}°`
  return `Holding at ${d.target}°`
}

/** "heating" → "Heating". */
function capital(word: string): string {
  return word.charAt(0).toUpperCase() + word.slice(1)
}
