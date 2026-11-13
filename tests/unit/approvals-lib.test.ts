// Approval tool names in words.
import { describe, expect, it } from 'vitest'
import { outcomeText, settledAs, toolLabel } from '../../src/lib/approvals'

describe('toolLabel', () => {
  it('names each of Jarvis’s PC tools, and anything else plainly', () => {
    expect(toolLabel('run_command')).toBe('Run a command')
    expect(toolLabel('run_windows')).toBe('Run a Windows command')
    expect(toolLabel('write_file')).toBe('Write a file')
    expect(toolLabel('edit_file')).toBe('Edit a file')
    expect(toolLabel('change_code')).toBe('Change Jarvis’s code')
    expect(toolLabel('apply_code_change')).toBe('Put the new code live')
    expect(toolLabel('change_setting')).toBe('Change a setting')
    expect(toolLabel('')).toBe('Do this')
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
