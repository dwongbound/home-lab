// What Jarvis's approval requests are called on the page. Jarvis names the
// tool that wants to run (run_command, write_file, ...); the chat shows it
// in words.

const TOOL_LABELS: Record<string, string> = {
  run_command: 'Run a command',
  run_windows: 'Run a Windows command',
  write_file: 'Write a file',
  edit_file: 'Edit a file',
}

/** The words for an approval's tool, e.g. "run_command" → "Run a command"; anything else → "Do this". */
export function toolLabel(tool: string): string {
  return TOOL_LABELS[tool] ?? 'Do this'
}
