// Approval tool names in words.
import { describe, expect, it } from 'vitest'
import { msUntilExpiry, readableSummary, settledAs, settledLine, toolLabel } from '../../src/lib/approvals'

describe('toolLabel', () => {
  it('names each of Jarvis’s PC tools, and anything else plainly', () => {
    expect(toolLabel('run_command')).toBe('Run a command')
    expect(toolLabel('run_windows')).toBe('Run a Windows command')
    expect(toolLabel('write_file')).toBe('Write a file')
    expect(toolLabel('edit_file')).toBe('Edit a file')
    expect(toolLabel('change_code')).toBe('Change Jarvis’s code')
    expect(toolLabel('apply_code_change')).toBe('Put the new code live')
    expect(toolLabel('change_setting')).toBe('Change a setting')
    expect(toolLabel('')).toBe('Needs your OK')
  })
})

describe('how a settled approval reads', () => {
  it('is yes, no, or held for later when he said wait', () => {
    expect(settledAs(true, false)).toBe('approved')
    expect(settledAs(false, false)).toBe('denied')
    expect(settledAs(false, true)).toBe('later')
  })

  it('writes a settled approval as one line: the answer, who gave it, and what it was', () => {
    const summary = 'Restart Jarvis'
    expect(settledLine({ outcome: 'approved', by: 'voice', summary })).toBe('Approved out loud: Restart Jarvis')
    expect(settledLine({ outcome: 'approved', by: 'telegram', summary })).toBe('Approved on Telegram: Restart Jarvis')
    expect(settledLine({ outcome: 'denied', by: 'page', summary })).toBe('Denied: Restart Jarvis')
    expect(settledLine({ outcome: 'later', by: 'voice', summary })).toBe('Holding for later: Restart Jarvis')
    expect(settledLine({ outcome: 'denied', by: 'timeout', summary })).toBe('Timed out: Restart Jarvis')
    // A raw tool call is still cleaned up.
    expect(settledLine({ outcome: 'approved', by: 'page', summary: 'Google Calendar delete_event (eventId=abc)' })).toBe('Approved: Google Calendar: delete event')
  })

  it('knows how long an approval has left, and never times out an unreadable time', () => {
    const now = Date.parse('2026-11-17T12:00:00Z')
    expect(msUntilExpiry('2026-11-17T12:00:30Z', now)).toBe(30_000)
    expect(msUntilExpiry('2026-11-17T11:59:00Z', now)).toBe(0)
    expect(msUntilExpiry('', now)).toBeNull()
    expect(msUntilExpiry('soon', now)).toBeNull()
  })
})

describe('readableSummary', () => {
  it('keeps plain words as they are', () => {
    const plain = 'Is it OK if I move Disneyland (Fun calendar) from Friday, Nov 13 to Tuesday, Dec 8, all day?'
    expect(readableSummary(plain)).toBe(plain)
  })

  it('never shows ids, addresses or key=value pairs from a raw tool call', () => {
    expect(readableSummary('Google Calendar delete_event (eventId=31ck5q57f9hbqfbh0b474pi, calendarId=rqj2qkvs9d6dukl7nn7ln6cm8g@group.calendar.google.com)')).toBe('Google Calendar: delete event')
    expect(readableSummary('Flying club app book_airplane: aircraft=N8318B, instructor=Matthew Large, start=2026-11-14T09:00')).toBe('Flying club app: book airplane')
    expect(readableSummary('title=Disneyland, start=2026-12-08T00:00, calendar=Fun')).toBe('Jarvis wants to make a change. Ask him what it is before saying yes.')
  })
})
