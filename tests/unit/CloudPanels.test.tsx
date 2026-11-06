// Cloud panels: the not-set-up state, threads grouped waiting-on-you
// first, and finished threads only on the full page.
import { describe, expect, it } from 'vitest'
import { render, screen, within } from '@testing-library/react'
import { CalendarPanel, ClaudeThreadsPanel } from '../../src/components/CloudPanels'
import type { CloudDigest } from '../../src/types'

const now = new Date('2026-11-06T18:00:00Z')

/** A digest with one thread in each interesting state. */
function digest(): CloudDigest {
  const thread = (id: string, title: string, state: CloudDigest['threads'][number]['state']) =>
    ({ id, title, state, lastActivityAt: '2026-11-06T17:50:00Z', url: `https://claude.ai/x?thread=${id}` })
  return {
    updatedAt: '2026-11-06T17:48:00Z',
    threads: [thread('a', 'Ship rules', 'working'), thread('b', 'Declare scopes', 'blocked'), thread('c', 'Dinner', 'done')],
    calendar: [], email: [], deploys: [], pullRequests: [],
  }
}

describe('ClaudeThreadsPanel', () => {
  it('explains how to set it up when there is no digest', () => {
    render(<ClaudeThreadsPanel cloud={null} now={now} />)
    expect(screen.getByText(/once the hourly digest is set up/)).toBeInTheDocument()
  })

  it('shows waiting-on-you first, links each thread, and says how old the digest is', () => {
    render(<ClaudeThreadsPanel cloud={digest()} now={now} />)
    expect(screen.getByText('Updated 12 min ago')).toBeInTheDocument()
    const headings = screen.getAllByRole('heading', { level: 3 }).map((h) => h.textContent)
    expect(headings).toEqual(['Waiting on you 1', 'Working 1', 'Finished 1'])
    expect(screen.getByRole('link', { name: 'Declare scopes' })).toHaveAttribute('href', 'https://claude.ai/x?thread=b')
  })

  it('compact mode counts finished threads instead of listing them', () => {
    render(<ClaudeThreadsPanel cloud={digest()} now={now} compact />)
    expect(screen.queryByRole('link', { name: 'Dinner' })).not.toBeInTheDocument()
    expect(screen.getByText('1 finished')).toBeInTheDocument()
  })
})

describe('CalendarPanel', () => {
  it('says the day is free when there are no events', () => {
    render(<CalendarPanel cloud={digest()} now={now} />)
    const panel = screen.getByRole('region', { name: 'Calendar' })
    expect(within(panel).getByText('Nothing on your calendars today.')).toBeInTheDocument()
  })
})
