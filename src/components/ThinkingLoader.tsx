// The full-page loader while the first snapshot is on its way: Jarvis's orb
// (the one in the top bar, grown up) breathing inside two tilted orbits, with
// sparks circling it and "Jarvis is thinking..." with dots that bounce.
// Nothing here is glass, so it can move freely. With reduced motion it's a
// still, glowing orb, and the words still say what's happening.

/** The full-page "Jarvis is thinking..." loader, announced to screen readers. */
export function ThinkingLoader() {
  return (
    <div className="thinking" role="status">
      <div className="thinking__orb" aria-hidden="true">
        <span className="thinking__halo" />
        <span className="thinking__orbit thinking__orbit--a"><span className="thinking__spark" /></span>
        <span className="thinking__orbit thinking__orbit--b"><span className="thinking__spark" /></span>
        <span className="thinking__orbit thinking__orbit--c"><span className="thinking__spark" /></span>
        <span className="thinking__core" />
      </div>
      <p className="thinking__label">
        Jarvis is thinking
        <span className="thinking__dots" aria-hidden="true"><span>.</span><span>.</span><span>.</span></span>
      </p>
    </div>
  )
}
