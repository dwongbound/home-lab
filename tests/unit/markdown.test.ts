import { describe, expect, it } from 'vitest'
import { parseMarkdown, parseSpans } from '../../src/lib/markdown'

describe('parseMarkdown', () => {
  it('keeps a plain reply as one paragraph with its line breaks', () => {
    expect(parseMarkdown('It is 64°.\nClear tonight.')).toEqual([
      { kind: 'paragraph', spans: [{ kind: 'text', text: 'It is 64°.\nClear tonight.' }] },
    ])
  })
  it('reads headings, lists, a divider and paragraphs', () => {
    const blocks = parseMarkdown('## Today\n- Church 10 AM\n- Golf 2 PM\n\n---\n1. First\n2. Second\n\nDone.')
    expect(blocks.map((b) => b.kind)).toEqual(['heading', 'list', 'rule', 'list', 'paragraph'])
    expect(blocks[0]).toEqual({ kind: 'heading', level: 2, spans: [{ kind: 'text', text: 'Today' }] })
    expect(blocks[1]).toMatchObject({ ordered: false, items: [[{ kind: 'text', text: 'Church 10 AM' }], [{ kind: 'text', text: 'Golf 2 PM' }]] })
    expect(blocks[3]).toMatchObject({ ordered: true, items: [[{ kind: 'text', text: 'First' }], [{ kind: 'text', text: 'Second' }]] })
  })
  it('reads a pipe table with a header row', () => {
    const [table] = parseMarkdown('| Item | Price |\n|---|---:|\n| A30 | $900 |\n| A20 | **$650** |')
    expect(table).toEqual({
      kind: 'table',
      header: [[{ kind: 'text', text: 'Item' }], [{ kind: 'text', text: 'Price' }]],
      rows: [
        [[{ kind: 'text', text: 'A30' }], [{ kind: 'text', text: '$900' }]],
        [[{ kind: 'text', text: 'A20' }], [{ kind: 'bold', text: '$650' }]],
      ],
    })
  })
  it('keeps fenced code as is, even with # and - inside', () => {
    expect(parseMarkdown('Run:\n```\n# a comment\n- not a list\n```')).toEqual([
      { kind: 'paragraph', spans: [{ kind: 'text', text: 'Run:' }] },
      { kind: 'code', text: '# a comment\n- not a list' },
    ])
  })
  it('never treats HTML as markup', () => {
    expect(parseMarkdown('<b>hi</b>')).toEqual([{ kind: 'paragraph', spans: [{ kind: 'text', text: '<b>hi</b>' }] }])
  })
})

describe('parseSpans', () => {
  it('reads bold, italic, code and links, and leaves stray stars alone', () => {
    expect(parseSpans('**Bold** and *soft* with `code` at [Bose](https://bose.com/x) 5*3')).toEqual([
      { kind: 'bold', text: 'Bold' },
      { kind: 'text', text: ' and ' },
      { kind: 'italic', text: 'soft' },
      { kind: 'text', text: ' with ' },
      { kind: 'code', text: 'code' },
      { kind: 'text', text: ' at ' },
      { kind: 'link', text: 'Bose', href: 'https://bose.com/x' },
      { kind: 'text', text: ' 5*3' },
    ])
  })
})
