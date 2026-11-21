// A night of sleep from the Apple Watch (Dylan, 2026-11-20). The iPhone app
// reads Health and posts one night at a time (POST /api/jarvis/health/sleep);
// Jarvis stores it, scores it and hands nights back (GET, Jarvis
// /health/sleep). The apps speak camelCase and Jarvis snake_case; the checks
// and the renaming both live here. Health numbers are never logged and never
// in the snapshot: only the signed-in caller sends or asks for them.

import { isDay } from './nutrition.mjs'

const STAGES = ['core', 'deep', 'rem', 'awake', 'unspecified']
const MAX_STAGES = 500
export const MAX_SLEEP_DAYS = 30
const DEFAULT_SLEEP_DAYS = 7

/** A finite number from min to max, or undefined when it isn't one. */
function within(value, min, max) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) return undefined
  return value
}

/** True for a moment written the ISO way ("2026-11-20T00:40:00-08:00"). */
function isMoment(value) {
  return typeof value === 'string' && value.length <= 40 && !Number.isNaN(Date.parse(value))
}

/** A finite number, or null. */
function numberOrNull(value) {
  return typeof value === 'number' && Number.isFinite(value) ? value : null
}

/** An {avg, min} pair with both in range, undefined when absent, or null when one is out of range. */
function cleanPair(raw, min, max) {
  if (raw === undefined || raw === null) return undefined
  const pair = {}
  for (const key of ['avg', 'min']) {
    if (raw[key] === undefined || raw[key] === null) continue
    const value = within(raw[key], min, max)
    if (value === undefined) return null
    pair[key] = value
  }
  return pair
}

// The single readings a night may carry: the app's name, Jarvis's name and the range he accepts.
const READINGS = [
  ['hrvMs', 'hrv_ms', 1, 300],
  ['hrvRmssdMs', 'hrv_rmssd_ms', 1, 300],
  ['respiratoryRate', 'respiratory_rate', 4, 40],
  ['wristTempC', 'wrist_temp_c', 25, 42],
  ['breathingDisturbances', 'breathing_disturbances', 0, 200],
]

// The start and end moments a night may carry: the app's name and Jarvis's.
const MOMENTS = [
  ['inBedStart', 'in_bed_start'],
  ['inBedEnd', 'in_bed_end'],
  ['asleepStart', 'asleep_start'],
  ['asleepEnd', 'asleep_end'],
]

/**
 * Checks one night sent by the app and gives it back in Jarvis's shape:
 * {night} when it's good, {problem} in plain words when it isn't.
 */
export function cleanSleepNight(raw) {
  if (!isDay(raw?.night)) return { problem: 'Send night as YYYY-MM-DD' }
  if (!Array.isArray(raw.stages) || raw.stages.length === 0 || raw.stages.length > MAX_STAGES) {
    return { problem: `Send 1 to ${MAX_STAGES} stages` }
  }
  const stages = []
  for (const stage of raw.stages) {
    if (!STAGES.includes(stage?.stage) || !isMoment(stage.start) || !isMoment(stage.end)) {
      return { problem: `Each stage needs a stage (${STAGES.join(', ')}), a start and an end` }
    }
    stages.push({ stage: stage.stage, start: stage.start, end: stage.end })
  }
  const night = { night: raw.night, stages }
  for (const [ours, his] of MOMENTS) {
    if (raw[ours] === undefined || raw[ours] === null) continue
    if (!isMoment(raw[ours])) return { problem: `${ours} isn't a time` }
    night[his] = raw[ours]
  }
  for (const [ours, his, min, max] of READINGS) {
    if (raw[ours] === undefined || raw[ours] === null) continue
    const value = within(raw[ours], min, max)
    if (value === undefined) return { problem: `${ours} must be between ${min} and ${max}` }
    night[his] = value
  }
  const heart = cleanPair(raw.heartRate, 25, 220)
  if (heart === null) return { problem: 'heartRate must be between 25 and 220' }
  if (heart !== undefined) night.heart_rate = heart
  const oxygen = cleanPair(raw.spo2, 50, 100)
  if (oxygen === null) return { problem: 'spo2 must be between 50 and 100 (percent)' }
  if (oxygen !== undefined) night.spo2 = oxygen
  if (typeof raw.source === 'string' && raw.source.trim() !== '') night.source = raw.source.trim().slice(0, 80)
  return { night }
}

/** How many nights to send for a `days` from the address: 7 when it's missing, 1 to 30, or null when it isn't a whole number. */
export function sleepDayCount(value) {
  if (value === null || value === '') return DEFAULT_SLEEP_DAYS
  if (!/^\d{1,3}$/.test(value)) return null
  return Math.min(MAX_SLEEP_DAYS, Math.max(1, Number(value)))
}

/** An {avg, min} pair from Jarvis, or null when he has neither. */
function parsePair(raw) {
  const pair = { avg: numberOrNull(raw?.avg), min: numberOrNull(raw?.min) }
  if (pair.avg === null && pair.min === null) return null
  return pair
}

/** The three parts of the score, or null when the night has none. */
function parseParts(raw) {
  if (!raw || typeof raw !== 'object') return null
  return { duration: numberOrNull(raw.duration), consistency: numberOrNull(raw.consistency), interruptions: numberOrNull(raw.interruptions) }
}

/** One of Jarvis's nights in the apps' shape, or null when it has no date. */
export function parseSleepNight(raw) {
  if (!isDay(raw?.night)) return null
  const minutes = raw.minutes ?? {}
  const vitals = raw.vitals ?? {}
  let scoreSource = null
  if (raw.score_source === 'jarvis' || raw.score_source === 'apple') scoreSource = raw.score_source
  return {
    night: raw.night,
    bedtime: isMoment(raw.bedtime) ? raw.bedtime : null,
    wake: isMoment(raw.wake) ? raw.wake : null,
    minutes: {
      asleep: numberOrNull(minutes.asleep),
      inBed: numberOrNull(minutes.in_bed),
      awake: numberOrNull(minutes.awake),
      deep: numberOrNull(minutes.deep),
      rem: numberOrNull(minutes.rem),
      core: numberOrNull(minutes.core),
      unspecified: numberOrNull(minutes.unspecified),
    },
    interruptions: numberOrNull(raw.interruptions),
    vitals: {
      heartRate: parsePair(vitals.heart_rate),
      hrvMs: numberOrNull(vitals.hrv_ms),
      hrvRmssdMs: numberOrNull(vitals.hrv_rmssd_ms),
      respiratoryRate: numberOrNull(vitals.respiratory_rate),
      spo2: parsePair(vitals.spo2),
      wristTempC: numberOrNull(vitals.wrist_temp_c),
      wristTempDeltaC: numberOrNull(vitals.wrist_temp_delta_c),
      breathingDisturbances: numberOrNull(vitals.breathing_disturbances),
    },
    // Out of 100; Jarvis's own estimate unless scoreSource says otherwise.
    score: numberOrNull(raw.score),
    scoreSource,
    scoreBand: scoreBand(numberOrNull(raw.score)),
    scoreParts: parseParts(raw.score_parts),
    // The night as a timeline; empty when Jarvis no longer has the detail.
    stages: parseStages(raw.stages),
  }
}

/** The word for a score, the same bands Jarvis uses when he talks: 85 great, 70 good, 50 fair, under that poor. */
export function scoreBand(score) {
  if (score === null) return null
  if (score >= 85) return 'great'
  if (score >= 70) return 'good'
  if (score >= 50) return 'fair'
  return 'poor'
}

/** The stage segments of a night in time order, dropping broken ones. */
function parseStages(raw) {
  if (!Array.isArray(raw)) return []
  const stages = raw
    .filter((one) => STAGES.includes(one?.stage) && isMoment(one.start) && isMoment(one.end))
    .slice(0, MAX_STAGES)
    .map((one) => ({ stage: one.stage, start: one.start, end: one.end }))
  stages.sort((a, b) => Date.parse(a.start) - Date.parse(b.start))
  return stages
}

const TREND_NIGHTS = 7

/**
 * Sleep for the snapshot (Home and the TV carousel, no extra request): the
 * latest night without its timeline, plus up to seven nights of score and
 * time asleep, newest first. Null when there are no nights.
 */
export function sleepSummary(nights) {
  if (!Array.isArray(nights) || nights.length === 0) return null
  const last = { ...nights[0] }
  // The timeline is only for the detail screen, which asks for it itself.
  delete last.stages
  const trend = nights.slice(0, TREND_NIGHTS).map((night) => ({ night: night.night, score: night.score, asleep: night.minutes.asleep }))
  return { last, trend }
}

/** Jarvis's list of nights, newest first, or null when it isn't one. */
export function parseSleepNights(raw) {
  if (!Array.isArray(raw?.nights)) return null
  const nights = raw.nights.map(parseSleepNight).filter((night) => night !== null).slice(0, MAX_SLEEP_DAYS)
  nights.sort((a, b) => b.night.localeCompare(a.night))
  return nights
}
