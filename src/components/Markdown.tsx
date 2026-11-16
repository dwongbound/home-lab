import { Fragment } from 'react'
import { parseMarkdown, type Block, type Span } from '../lib/markdown'

/** Jarvis's reply as rich text: headings, lists, tables, dividers, code (Dylan, 2026-11-16). */
export function Markdown({ text }: { text: string }) {
  return <>{parseMarkdown(text).map((block, i) => <BlockView key={i} block={block} />)}</>
}

/** One block of the reply. */
function BlockView({ block }: { block: Block }) {
  if (block.kind === 'heading') {
    const spans = <Spans spans={block.spans} />
    if (block.level === 1) return <h3 className="md__h md__h1">{spans}</h3>
    if (block.level === 2) return <h4 className="md__h md__h2">{spans}</h4>
    return <h5 className="md__h md__h3">{spans}</h5>
  }
  if (block.kind === 'paragraph') return <p className="md__p"><Spans spans={block.spans} /></p>
  if (block.kind === 'list') {
    const items = block.items.map((item, i) => <li key={i}><Spans spans={item} /></li>)
    return block.ordered ? <ol className="md__list">{items}</ol> : <ul className="md__list">{items}</ul>
  }
  if (block.kind === 'table') {
    return (
      <div className="md__scroll">
        <table className="md__table">
          <thead><tr>{block.header.map((cell, i) => <th key={i}><Spans spans={cell} /></th>)}</tr></thead>
          <tbody>
            {block.rows.map((row, r) => (
              <tr key={r}>{row.map((cell, c) => <td key={c}><Spans spans={cell} /></td>)}</tr>
            ))}
          </tbody>
        </table>
      </div>
    )
  }
  if (block.kind === 'rule') return <hr className="md__rule" />
  return <pre className="md__code"><code>{block.text}</code></pre>
}

/** The styled pieces of one line. */
function Spans({ spans }: { spans: Span[] }) {
  return (
    <>
      {spans.map((span, i) => {
        if (span.kind === 'bold') return <strong key={i}>{span.text}</strong>
        if (span.kind === 'italic') return <em key={i}>{span.text}</em>
        if (span.kind === 'code') return <code key={i} className="md__inline">{span.text}</code>
        // Links open elsewhere so the chat (and Talk) stay where they are.
        if (span.kind === 'link') return <a key={i} href={span.href} target="_blank" rel="noreferrer">{span.text}</a>
        return <Fragment key={i}>{span.text}</Fragment>
      })}
    </>
  )
}
