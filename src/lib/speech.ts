// Reading Jarvis's reply aloud with the browser's own voice, calling back
// on every word so the orb can pulse with it. This is the stand-in for the
// mockup: the real build plays Jarvis's voice from the PC and measures its
// loudness instead. Browsers without speech just stay quiet.

/** True when this browser can speak. */
export function canSpeak(): boolean {
  return typeof window !== 'undefined' && 'speechSynthesis' in window && typeof SpeechSynthesisUtterance === 'function'
}

/** Stops anything being read aloud. */
export function stopSpeaking(): void {
  if (canSpeak()) window.speechSynthesis.cancel()
}

/**
 * Reads text aloud. onWord fires for each word (from the browser's word
 * events, or a steady beat when the browser doesn't send them, as some
 * iOS voices don't). Resolves when it finishes or is stopped.
 */
export function speak(text: string, onWord: () => void): Promise<void> {
  if (!canSpeak() || text.trim() === '') return Promise.resolve()
  stopSpeaking()
  return new Promise((resolve) => {
    const u = new SpeechSynthesisUtterance(text)
    u.rate = 1.05
    let gotWordEvents = false
    let beat = 0
    u.onstart = () => {
      // No word events within half a second: beat at a talking pace instead.
      beat = window.setTimeout(function fallback() {
        if (gotWordEvents) return
        onWord()
        beat = window.setTimeout(fallback, 170 + Math.random() * 120)
      }, 500)
    }
    u.onboundary = (e) => {
      if (e.name && e.name !== 'word') return
      gotWordEvents = true
      onWord()
    }
    const done = () => { window.clearTimeout(beat); resolve() }
    u.onend = done
    u.onerror = done
    window.speechSynthesis.speak(u)
  })
}
