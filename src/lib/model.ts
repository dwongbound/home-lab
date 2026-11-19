// Which brain answered a chat turn (Dylan, 2026-11-16): Claude most of the
// time, Ornith (the local model) when Claude's plan is out of room. Jarvis
// names the model with each reply; the chat shows it as a small chip over
// the reply, orange for Claude and blue for anything local. Since 2026-11-17
// the chip also says which Claude model: (CO), (CH), (CS), (CF).

/** The letter for each Claude model, matched anywhere in the name Jarvis sends ("claude-opus-5-5", "opus"). */
const CLAUDE_LETTERS: [string, string][] = [
  ['opus', 'O'],
  ['haiku', 'H'],
  ['sonnet', 'S'],
  ['fable', 'F'],
]

/** True when the name is Claude or one of Claude's models ("claude", "claude-opus-5-5", "opus"). */
function isClaudeModel(name: string): boolean {
  if (name.startsWith('claude')) return true
  return CLAUDE_LETTERS.some(([word]) => name === word)
}

// Messages Jarvis sends unasked (a reminder, a Lookout ping, the start of
// day) sit in the chat as turns whose model is "notice:" + where they came
// from (Dylan going Telegram-free, 2026-11-18). Their chip names who wrote
// them like any reply, then says where they came from in grey: "Jarvis (CO)
// Lookout" (Dylan, 2026-11-18: "this should also say jarvis or ornith").
// Jarvis names the writer in the turn's `writer`; with none (a plain
// reminder no model wrote) the chip is "Jarvis" and the word.
const NOTICE_PREFIX = 'notice:'
const NOTICE_LABELS: Record<string, string> = {
  reminder: 'Reminder',
  lookout: 'Lookout',
  alert: 'Alert',
  job: 'Finished',
  digest: 'Digest',
}

/** True when the turn is a message Jarvis sent unasked, not a reply. */
function isNoticeModel(model: string): boolean {
  return model.trim().toLowerCase().startsWith(NOTICE_PREFIX)
}

/** "Reminder", "Lookout"...; '' for a source he hasn't named a word for. */
function noticeWord(model: string): string {
  return NOTICE_LABELS[model.trim().toLowerCase().slice(NOTICE_PREFIX.length)] ?? ''
}

/**
 * The chip's text. Claude models get two letters (Dylan, 2026-11-17):
 * "Jarvis (CO)" Opus, "Jarvis (CH)" Haiku, "Jarvis (CS)" Sonnet, "Jarvis (CF)"
 * Fable. A bare "claude" (an older Jarvis that doesn't say which) stays
 * "Jarvis (C)". Anything else gets its initial: "Jarvis (O)" for Ornith.
 */
export function modelLabel(model: string): string {
  const name = model.trim().toLowerCase()
  if (!name) return ''
  if (isClaudeModel(name)) {
    const found = CLAUDE_LETTERS.find(([word]) => name.includes(word))
    if (found) return `Jarvis (C${found[1]})`
    return 'Jarvis (C)'
  }
  return `Jarvis (${name[0].toUpperCase()})`
}

/** The chip's colour family: Claude (any of its models) is orange, every local model is blue. */
export function modelTone(model: string): 'claude' | 'local' {
  return isClaudeModel(model.trim().toLowerCase()) ? 'claude' : 'local'
}

/** What a chip shows: who wrote it, its colour, and for an unasked message where it came from. */
export interface Chip { label: string; tone: 'claude' | 'local' | 'notice'; source: string }

/**
 * The chip for one turn. A reply: its model's label and colour. An unasked
 * message: the writer's label and colour (plain "Jarvis" when no model
 * wrote it) plus the source word, "Lookout", "Reminder", "Finished".
 */
export function chipFor(model: string, writer = ''): Chip {
  if (!isNoticeModel(model)) return { label: modelLabel(model), tone: modelTone(model), source: '' }
  const source = noticeWord(model)
  if (!writer.trim()) return { label: 'Jarvis', tone: 'notice', source }
  return { label: modelLabel(writer), tone: modelTone(writer), source }
}
