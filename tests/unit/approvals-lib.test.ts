// Approval tool names in words.
import { describe, expect, it } from 'vitest'
import { outcomeText, readableSummary, settledAs, toolLabel } from '../../src/lib/approvals'

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

  it('says who answered, and that a held one waits for "go ahead"', () => {
    expect(outcomeText({ outcome: 'approved', by: 'voice' })).toBe('Approved out loud')
    expect(outcomeText({ outcome: 'denied', by: 'page' })).toBe('Denied')
    expect(outcomeText({ outcome: 'later', by: 'voice' })).toBe('Holding this for later. Say “go ahead” when you’re ready.')
    expect(outcomeText({ outcome: 'denied', by: 'timeout' })).toBe('No answer in time, so he left it alone')
  })
})

describe('readableSummary', () => {
  it('keeps plain words as they are', () => {
    const plain = 'Is it OK if I move Disneyland (Fun calendar) from Friday, Nov 13 to Tuesday, Dec 8, all day?'
    expect(readableSummary(plain)).toBe(plain)
  })

  it('never shows ids, addresses or key=value pairs from a raw tool call', () => {
    expect(readableSummary('Google Calendar delete_event (eventId=31ck5q57f9hbqfbh0b474pi, calendarId=rqj2qkvs9d6dukl7nn7ln6cm8g@group.calendar.google.com)')).toBe('Google Calendar: delete event')
    expect(readableSummary('title=Disneyland, start=2026-12-08T00:00, calendar=Fun')).toBe('Jarvis wants to make a change. Ask him what it is before saying yes.')
  })
})
