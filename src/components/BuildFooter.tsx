import { builtLabel, commitUrl } from '../lib/build'

/**
 * One faint line at the bottom of the page: the build's commit (linked to
 * GitHub) and when it was deployed, so he can tell which version he's on.
 */
export function BuildFooter() {
  const sha = __BUILD_SHA__.slice(0, 7)
  const url = commitUrl(__BUILD_SHA__)
  const built = builtLabel(__BUILT_AT__)
  return (
    <footer className="build">
      <span>build </span>
      {url ? <a href={url} target="_blank" rel="noreferrer">{sha}</a> : <span>{sha}</span>}
      {built ? <span> · deployed {built}</span> : null}
    </footer>
  )
}
