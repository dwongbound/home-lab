// The backdrop is a painted window onto the sky outside, and it follows
// the real time of day on the PC: the one deliberate flourish on the page.
export type SkyPhase = 'night' | 'dawn' | 'day' | 'dusk'

/** Which sky to paint for a time: dawn 5:30, day 8:00, dusk 4:30 pm, night 8 pm. */
export function skyPhase(date: Date): SkyPhase {
  const h = date.getHours() + date.getMinutes() / 60
  if (h < 5.5 || h >= 20) return 'night'
  if (h < 8) return 'dawn'
  if (h < 16.5) return 'day'
  return 'dusk'
}

/** The sky on screen: the Settings choice, or the clock's when it's "auto" or unset. */
export function shownPhase(date: Date, override?: string | null): SkyPhase {
  if (override && override !== 'auto') return override as SkyPhase
  return skyPhase(date)
}
