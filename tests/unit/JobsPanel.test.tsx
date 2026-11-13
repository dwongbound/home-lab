// "What Jarvis is doing" on the Services page: the three main jobs, what
// Lookout is watching and held back, and the quiet housekeeping.
import { describe, expect, it } from 'vitest'
import { render, screen } from '@testing-library/react'
import { JobsPanel, inTime, modelLabel } from '../../src/components/JobsPanel'
import type { JarvisJobs } from '../../src/types'

const now = new Date('2026-11-13T01:00:00Z')

const jobs: JarvisJobs = {
  generatedAt: '2026-11-13T01:00:00Z',
  jobs: [
    { id: 'lookout', name: 'Lookout', group: 'main', model: 'ornith-1.5:9b', schedule: 'Every 30 min while you’re awake', status: 'ok', lastRun: '2026-11-13T00:49:00Z', nextRun: '2026-11-13T01:19:00Z', lastResult: 'Nothing worth a ping.' },
    { id: 'nightly', name: 'Nightly', group: 'main', model: 'claude-opus-5-5', schedule: 'Every night at 3:30 AM', status: 'error', lastRun: null, nextRun: null, lastResult: null },
    { id: 'housekeeping-nutrition', name: 'Nutrition sync', group: 'housekeeping', model: null, schedule: 'Hourly', status: 'ok', lastRun: '2026-11-13T00:20:00Z', nextRun: null, lastResult: null },
  ],
  lookout: { checks: ['drive_time', 'place_weather'], watching: ['Volleyball at 8 PM'], heldBack: [{ text: 'SPY down 0.8%', reason: 'A normal move.' }] },
  messenger: { sentToday: 2, cap: 5, quiet: 'Sleeping' },
}

describe('JobsPanel', () => {
  it('shows each main job with its model, last result and timing', () => {
    render(<JobsPanel jobs={jobs} now={now} />)
    expect(screen.getByText('2 of 5 pings sent today · Quiet: Sleeping')).toBeInTheDocument()
    expect(screen.getByText('Ornith on the PC · Every 30 min while you’re awake')).toBeInTheDocument()
    expect(screen.getByText('Nothing worth a ping.')).toBeInTheDocument()
    expect(screen.getByText('Ran 11 min ago · next in 19 min')).toBeInTheDocument()
    expect(screen.getByText('Hasn’t run yet')).toBeInTheDocument()
    expect(screen.getByText('Error')).toBeInTheDocument()
  })

  it('lists what Lookout checked, is watching and held back, and the housekeeping', () => {
    render(<JobsPanel jobs={jobs} now={now} />)
    expect(screen.getByText('Last looked at: drive time, place weather')).toBeInTheDocument()
    expect(screen.getByText('Volleyball at 8 PM')).toBeInTheDocument()
    expect(screen.getByText(/SPY down 0.8%/)).toBeInTheDocument()
    expect(screen.getByText(/A normal move/)).toBeInTheDocument()
    expect(screen.getByText('Nutrition sync')).toBeInTheDocument()
  })

  it('says so when Jarvis doesn’t report its jobs', () => {
    render(<JobsPanel jobs={null} now={now} />)
    expect(screen.getByText(/isn’t reporting its background jobs/)).toBeInTheDocument()
  })

  it('names models and times in plain words', () => {
    expect(modelLabel('claude-opus-5-5')).toBe('Opus')
    expect(modelLabel('claude-haiku-5-5')).toBe('Haiku')
    expect(modelLabel(null)).toBeNull()
    expect(inTime('2026-11-13T04:00:00Z', now)).toBe('in 3 h')
    expect(inTime('2026-11-13T00:00:00Z', now)).toBe('now')
  })
})
