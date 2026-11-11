// Where money-picks.mjs keeps its list on the PC: one JSON file. Separate
// from the store so the browser preview (which runs the mock source) never
// pulls in Node's file system.
import { mkdir, readFile, rename, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

/** File storage for the pick store, or null when no file is set (keep in memory). */
export function createPickFile(file) {
  if (!file) return null
  return {
    /** The saved list, or null when there's no file yet. Broken JSON throws (the store starts empty). */
    async load() {
      let raw
      try {
        raw = await readFile(file, 'utf8')
      } catch (err) {
        if (err?.code === 'ENOENT') return null
        throw err
      }
      return JSON.parse(raw)
    },

    /** Writes a temp file and renames it over the old one, so a crash never leaves half a file. */
    async save(state) {
      await mkdir(dirname(file), { recursive: true })
      const temp = `${file}.tmp`
      await writeFile(temp, JSON.stringify(state, null, 2))
      await rename(temp, file)
    },
  }
}
