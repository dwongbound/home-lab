// The blocking indicator for anything waiting on the network. With reduced
// motion it stays a still ring, and the label still says what's happening.

/** A spinner with a visible label, announced to screen readers. */
export function Spinner({ label }: { label: string }) {
  return (
    <span className="spinner" role="status">
      <span className="spinner__ring" aria-hidden="true" />
      <span className="spinner__label">{label}</span>
    </span>
  )
}
