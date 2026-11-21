import { describe, expect, it } from 'vitest'
import { cleanSleepNight, parseSleepNight, parseSleepNights, scoreBand, sleepDayCount, sleepSummary } from '../../server/sources/sleep.mjs'

const stage = { stage: 'core', start: '2026-11-20T00:40:00-08:00', end: '2026-11-20T02:10:00-08:00' }

describe('cleanSleepNight', () => {
  it("turns the app's night into Jarvis's names and leaves out what wasn't sent", () => {
    const checked = cleanSleepNight({
      night: '2026-11-20', inBedStart: '2026-11-20T00:30:00-08:00', inBedEnd: '2026-11-20T08:10:00-08:00',
      stages: [stage, { stage: 'unspecified', start: '2026-11-20T02:10:00-08:00', end: '2026-11-20T02:30:00-08:00', extra: 1 }],
      heartRate: { avg: 54, min: 47 }, hrvMs: 48, hrvRmssdMs: 52, respiratoryRate: 14.5, spo2: { avg: 96 }, wristTempC: 35.4, breathingDisturbances: 2,
      source: ' Apple Watch ', appleScore: 81, notes: 'ignored',
    })
    expect(checked.night).toEqual({
      night: '2026-11-20', in_bed_start: '2026-11-20T00:30:00-08:00', in_bed_end: '2026-11-20T08:10:00-08:00',
      stages: [stage, { stage: 'unspecified', start: '2026-11-20T02:10:00-08:00', end: '2026-11-20T02:30:00-08:00' }],
      heart_rate: { avg: 54, min: 47 }, hrv_ms: 48, hrv_rmssd_ms: 52, respiratory_rate: 14.5, spo2: { avg: 96 }, wrist_temp_c: 35.4, breathing_disturbances: 2,
      source: 'Apple Watch',
    })
    expect(cleanSleepNight({ night: '2026-11-20', stages: [stage], hrvMs: null }).night).toEqual({ night: '2026-11-20', stages: [stage] })
  })

  it('says plainly what is wrong with a bad night', () => {
    expect(cleanSleepNight(null).problem).toBe('Send night as YYYY-MM-DD')
    expect(cleanSleepNight({ night: 'last night', stages: [stage] }).problem).toBe('Send night as YYYY-MM-DD')
    expect(cleanSleepNight({ night: '2026-11-20', stages: [] }).problem).toBe('Send 1 to 500 stages')
    expect(cleanSleepNight({ night: '2026-11-20', stages: Array(501).fill(stage) }).problem).toBe('Send 1 to 500 stages')
    expect(cleanSleepNight({ night: '2026-11-20', stages: [{ ...stage, stage: 'nap' }] }).problem).toContain('Each stage needs')
    expect(cleanSleepNight({ night: '2026-11-20', stages: [{ ...stage, end: 'later' }] }).problem).toContain('Each stage needs')
    expect(cleanSleepNight({ night: '2026-11-20', stages: [stage], inBedStart: 'midnight' }).problem).toBe("inBedStart isn't a time")
    expect(cleanSleepNight({ night: '2026-11-20', stages: [stage], hrvMs: 900 }).problem).toBe('hrvMs must be between 1 and 300')
    expect(cleanSleepNight({ night: '2026-11-20', stages: [stage], heartRate: { avg: 10 } }).problem).toBe('heartRate must be between 25 and 220')
    // A fraction means the app forgot to turn it into a percentage.
    expect(cleanSleepNight({ night: '2026-11-20', stages: [stage], spo2: { avg: 0.96 } }).problem).toBe('spo2 must be between 50 and 100 (percent)')
  })
})

describe('sleepDayCount', () => {
  it('is 7 by default, 1 to 30, and null for anything else', () => {
    expect(sleepDayCount(null)).toBe(7)
    expect(sleepDayCount('')).toBe(7)
    expect(sleepDayCount('14')).toBe(14)
    expect(sleepDayCount('0')).toBe(1)
    expect(sleepDayCount('99')).toBe(30)
    expect(sleepDayCount('a week')).toBeNull()
  })
})

const jarvisNight = {
  night: '2026-11-20', bedtime: '2026-11-20T00:40:00-08:00', wake: '2026-11-20T08:00:00-08:00',
  minutes: { asleep: 420, in_bed: 450, awake: 20, deep: 70, rem: 95, core: 255, unspecified: 0 },
  interruptions: 1,
  vitals: { heart_rate: { avg: 54, min: 47 }, hrv_ms: 48, hrv_rmssd_ms: null, respiratory_rate: 14.5, spo2: null, wrist_temp_c: 35.4, wrist_temp_delta_c: -0.3, breathing_disturbances: 2 },
  score: 78, score_source: 'jarvis', score_parts: { duration: 44, consistency: null, interruptions: 16 }, score_max: { duration: 50 },
  stages: [{ stage: 'deep', start: '2026-11-20T02:10:00-08:00', end: '2026-11-20T03:20:00-08:00' }, stage, { stage: 'nap', start: 'x', end: 'y' }],
  source: 'watch', updated_at: '2026-11-20T19:00:00Z',
}

describe('parseSleepNight', () => {
  it("gives Jarvis's night in the apps' names, with a band and the timeline in order", () => {
    expect(parseSleepNight(jarvisNight)).toEqual({
      night: '2026-11-20', bedtime: '2026-11-20T00:40:00-08:00', wake: '2026-11-20T08:00:00-08:00',
      minutes: { asleep: 420, inBed: 450, awake: 20, deep: 70, rem: 95, core: 255, unspecified: 0 },
      interruptions: 1,
      vitals: { heartRate: { avg: 54, min: 47 }, hrvMs: 48, hrvRmssdMs: null, respiratoryRate: 14.5, spo2: null, wristTempC: 35.4, wristTempDeltaC: -0.3, breathingDisturbances: 2 },
      score: 78, scoreSource: 'jarvis', scoreBand: 'good', scoreParts: { duration: 44, consistency: null, interruptions: 16 },
      stages: [stage, { stage: 'deep', start: '2026-11-20T02:10:00-08:00', end: '2026-11-20T03:20:00-08:00' }],
    })
  })

  it('fills a bare night with nulls, and is null without a date', () => {
    const bare = parseSleepNight({ night: '2026-11-19' })
    expect(bare).toMatchObject({ bedtime: null, interruptions: null, score: null, scoreSource: null, scoreBand: null, scoreParts: null, stages: [] })
    expect(bare?.vitals.heartRate).toBeNull()
    expect(bare?.minutes.asleep).toBeNull()
    expect(parseSleepNight({ night: 'tuesday' })).toBeNull()
    expect(parseSleepNight(null)).toBeNull()
  })
})

describe('scoreBand', () => {
  it('names a score the way Jarvis says it', () => {
    expect([scoreBand(92), scoreBand(85), scoreBand(84), scoreBand(70), scoreBand(69), scoreBand(50), scoreBand(41), scoreBand(null)]).toEqual(['great', 'great', 'good', 'good', 'fair', 'fair', 'poor', null])
  })
})

describe('parseSleepNights and sleepSummary', () => {
  it('lists nights newest first and sums them up for the snapshot without the timeline', () => {
    const nights = parseSleepNights({ nights: [{ night: '2026-11-18', score: 60, minutes: { asleep: 380 } }, jarvisNight, { night: 'nope' }] })
    expect(nights?.map((night: { night: string }) => night.night)).toEqual(['2026-11-20', '2026-11-18'])
    const summary = sleepSummary(nights)
    expect(summary?.last.night).toBe('2026-11-20')
    expect(summary?.last).not.toHaveProperty('stages')
    expect(summary?.trend).toEqual([{ night: '2026-11-20', score: 78, asleep: 420 }, { night: '2026-11-18', score: 60, asleep: 380 }])
    // The night itself keeps its timeline for the detail screen.
    expect(nights?.[0].stages).toHaveLength(2)
  })

  it('is null when there is nothing to show', () => {
    expect(parseSleepNights({})).toBeNull()
    expect(sleepSummary(null)).toBeNull()
    expect(sleepSummary([])).toBeNull()
  })
})
