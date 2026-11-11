import { useEffect, useRef, type ReactNode } from 'react'
import { Icon } from './Icon'
import { useScrollLock } from '../useScrollLock'

// The pop-up behind every tappable row: a title, a few labelled facts,
// optional links out (Gmail, Calendar, GitHub) and any extra content. Native
// <dialog>, so focus trapping and Esc come from the browser. It's a fixed
// size so it never jumps; long content scrolls inside it.

export interface Fact { label: string; value: ReactNode }
export interface OutLink { label: string; href: string }

interface Props {
  title: string
  /** A short line under the title, like the category or the time. */
  sub?: ReactNode
  facts?: Fact[]
  links?: OutLink[]
  children?: ReactNode
  onClose: () => void
}

/** The detail dialog. Mount it to open it; unmount it to close it. */
export function DetailDialog({ title, sub, facts = [], links = [], children, onClose }: Props) {
  const ref = useRef<HTMLDialogElement>(null)
  useScrollLock()

  // Open as a modal on mount. jsdom (the unit test DOM) has no showModal,
  // so there it's just marked open.
  useEffect(() => {
    const d = ref.current
    if (!d || d.open) return
    if (typeof d.showModal === 'function') d.showModal()
    else d.setAttribute('open', '')
    // Hold focus on the box itself, not its first button: Safari otherwise
    // draws the keyboard-focus ring on that button as soon as it opens.
    d.focus()
    return () => { if (typeof d.close === 'function') d.close() }
  }, [])

  return (
    <dialog
      ref={ref}
      className="dialog dialog--detail glass"
      tabIndex={-1}
      aria-labelledby="detail-title"
      // Esc fires "cancel"; React closes it so the hash stays in step.
      onCancel={(e) => { e.preventDefault(); onClose() }}
      // A tap on the dimmed backdrop (outside the box) closes it too.
      onClick={(e) => { if (e.target === e.currentTarget) onClose() }}
    >
      <header className="detail__head">
        <div>
          <h2 id="detail-title" className="dialog__title">{title}</h2>
          {sub ? <p className="panel__sub">{sub}</p> : null}
        </div>
      </header>
      <div className="detail__body">
        {facts.length > 0 ? (
          <dl className="detail__facts">
            {facts.map((f) => (
              <div key={f.label} className="detail__fact"><dt>{f.label}</dt><dd>{f.value}</dd></div>
            ))}
          </dl>
        ) : null}
        {children}
      </div>
      <div className="dialog__actions">
        {links.map((l) => (
          <a key={l.href} className="btn detail__link" href={l.href} target="_blank" rel="noreferrer">
            {l.label} <Icon name="external" size={14} />
          </a>
        ))}
        <button type="button" className="btn btn--primary" onClick={onClose}>Close</button>
      </div>
    </dialog>
  )
}
