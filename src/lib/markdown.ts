// A small Markdown reader for Jarvis's chat replies (Dylan, 2026-11-16:
// "tables, headings, and sections and dividers etc should all be supported").
// It covers what he writes in the web chat and nothing more: headings,
// paragraphs, bullet and numbered lists, pipe tables, dividers, fenced code
// and, inline, bold, italic, code and links. No raw HTML ever gets through:
// the page renders these blocks itself (src/components/Markdown.tsx).

/** One piece of a line: plain words, or words with one style on them. */
export type Span =
  | { kind: 'text'; text: string }
  | { kind: 'bold'; text: string }
  | { kind: 'italic'; text: string }
  | { kind: 'code'; text: string }
  | { kind: 'link'; text: string; href: string }

/** One block of a reply. */
export type Block =
  | { kind: 'heading'; level: 1 | 2 | 3; spans: Span[] }
  | { kind: 'paragraph'; spans: Span[] }
  | { kind: 'list'; ordered: boolean; items: Span[][] }
  | { kind: 'table'; header: Span[][]; rows: Span[][][] }
  | { kind: 'rule' }
  | { kind: 'code'; text: string }

const HEADING = /^(#{1,3})\s+(.*)$/
const BULLET = /^\s*[-*•]\s+(.*)$/
const NUMBERED = /^\s*\d+[.)]\s+(.*)$/
const RULE = /^\s*(-{3,}|\*{3,}|_{3,})\s*$/
const FENCE = /^\s*```/
const TABLE_ROW = /^\s*\|.*\|\s*$/
const TABLE_DIVIDER = /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/

/** Reads a whole reply into blocks. Plain text comes back as paragraphs, line breaks kept. */
export function parseMarkdown(text: string): Block[] {
  const lines = text.replace(/\r\n?/g, '\n').split('\n')
  const blocks: Block[] = []
  let paragraph: string[] = []

  /** Closes the paragraph being gathered, if any. */
  function flush() {
    if (paragraph.length === 0) return
    blocks.push({ kind: 'paragraph', spans: parseSpans(paragraph.join('\n')) })
    paragraph = []
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i]
    if (FENCE.test(line)) {
      flush()
      const code: string[] = []
      i++
      while (i < lines.length && !FENCE.test(lines[i])) code.push(lines[i++])
      blocks.push({ kind: 'code', text: code.join('\n') })
      continue
    }
    if (line.trim() === '') { flush(); continue }
    if (RULE.test(line)) { flush(); blocks.push({ kind: 'rule' }); continue }
    const heading = HEADING.exec(line)
    if (heading) {
      flush()
      blocks.push({ kind: 'heading', level: heading[1].length as 1 | 2 | 3, spans: parseSpans(heading[2].trim()) })
      continue
    }
    if (TABLE_ROW.test(line) && i + 1 < lines.length && TABLE_DIVIDER.test(lines[i + 1])) {
      flush()
      const header = splitRow(line)
      const rows: Span[][][] = []
      i += 2
      while (i < lines.length && TABLE_ROW.test(lines[i])) rows.push(splitRow(lines[i++]))
      i--
      blocks.push({ kind: 'table', header, rows })
      continue
    }
    const bullet = BULLET.exec(line)
    const numbered = bullet ? null : NUMBERED.exec(line)
    if (bullet || numbered) {
      flush()
      const ordered = numbered !== null
      const items: Span[][] = []
      while (i < lines.length) {
        const item = ordered ? NUMBERED.exec(lines[i]) : BULLET.exec(lines[i])
        if (!item) break
        items.push(parseSpans(item[1].trim()))
        i++
      }
      i--
      blocks.push({ kind: 'list', ordered, items })
      continue
    }
    paragraph.push(line)
  }
  flush()
  return blocks
}

/** The cells of one "| a | b |" table line. */
function splitRow(line: string): Span[][] {
  const inner = line.trim().replace(/^\|/, '').replace(/\|$/, '')
  return inner.split('|').map((cell) => parseSpans(cell.trim()))
}

const INLINE = /(\*\*(.+?)\*\*|__(.+?)__|`([^`]+)`|\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)|(?<![\w*])\*([^*\n]+)\*(?![\w*])|(?<![\w_])_([^_\n]+)_(?![\w_]))/g

/** Reads bold, italic, code and links out of one run of text. */
export function parseSpans(text: string): Span[] {
  const spans: Span[] = []
  let last = 0
  for (const match of text.matchAll(INLINE)) {
    const at = match.index ?? 0
    if (at > last) spans.push({ kind: 'text', text: text.slice(last, at) })
    if (match[2] !== undefined || match[3] !== undefined) spans.push({ kind: 'bold', text: match[2] ?? match[3] })
    else if (match[4] !== undefined) spans.push({ kind: 'code', text: match[4] })
    else if (match[5] !== undefined) spans.push({ kind: 'link', text: match[5], href: match[6] })
    else spans.push({ kind: 'italic', text: match[7] ?? match[8] })
    last = at + match[0].length
  }
  if (last < text.length) spans.push({ kind: 'text', text: text.slice(last) })
  return spans
}
