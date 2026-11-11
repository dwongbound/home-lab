// Approval tool names in words.
import { describe, expect, it } from 'vitest'
import { toolLabel } from '../../src/lib/approvals'

describe('toolLabel', () => {
  it('names each of Jarvis’s PC tools, and anything else plainly', () => {
    expect(toolLabel('run_command')).toBe('Run a command')
    expect(toolLabel('run_windows')).toBe('Run a Windows command')
    expect(toolLabel('write_file')).toBe('Write a file')
    expect(toolLabel('edit_file')).toBe('Edit a file')
    expect(toolLabel('')).toBe('Do this')
  })
})
