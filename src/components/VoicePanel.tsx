import { useEffect, useRef, useState } from 'react'
import { fetchVoiceSample, saveVoice, useVoice } from '../api/client'
import type { VoiceChoice, VoiceOption, VoiceSettings } from '../types'
import { Spinner } from './Spinner'

// Voice on the Settings page: how Jarvis sounds when he talks back (Talk on
// the Overview). Pick one of Kokoro's voices, with a Play sample for each,
// set the speed, and optionally blend in a second voice. Save sends it to
// Jarvis, who uses it from his next reply; nothing is kept in the browser.

type Accent = 'gb' | 'us'
const ACCENTS: { id: Accent; label: string }[] = [
  { id: 'gb', label: 'British' },
  { id: 'us', label: 'American' },
]

/** "British · man", for under a voice's name. */
function voiceKind(v: VoiceOption): string {
  const accent = v.accent === 'gb' ? 'British' : 'American'
  const gender = v.gender === 'f' ? 'woman' : 'man'
  return `${accent} · ${gender}`
}

/** A voice's friendly name, or its id if it isn't in the list. */
function nameOf(voices: VoiceOption[], id: string): string {
  return voices.find((v) => v.id === id)?.name ?? id
}

/** "1.10×" for the speed label. */
function speedLabel(speed: number): string {
  return `${speed.toFixed(2)}×`
}

/** "70% George · 30% Lewis" for the blend slider. */
function mixLabel(voices: VoiceOption[], choice: VoiceChoice): string {
  if (!choice.blend) return ''
  const second = Math.round(choice.blend.mix * 100)
  return `${100 - second}% ${nameOf(voices, choice.voice)} · ${second}% ${nameOf(voices, choice.blend.voice2)}`
}

/** True when two choices would sound the same. */
function sameChoice(a: VoiceChoice, b: VoiceChoice): boolean {
  if (a.voice !== b.voice || a.speed !== b.speed) return false
  if (a.blend === null || b.blend === null) return a.blend === b.blend
  return a.blend.voice2 === b.blend.voice2 && a.blend.mix === b.blend.mix
}

/** The first voice that isn't `id`, for a blend's starting second voice. */
function otherVoice(voices: VoiceOption[], id: string): string {
  const current = voices.find((v) => v.id === id)
  const sameAccent = voices.find((v) => v.id !== id && v.accent === current?.accent && v.gender === current?.gender)
  return (sameAccent ?? voices.find((v) => v.id !== id) ?? { id }).id
}

/**
 * Plays WAV bytes and returns a function that stops them. Browsers without
 * blob URLs or audio (tests) just stay quiet; onEnd still fires.
 */
function playWav(audio: Uint8Array, onEnd: () => void): () => void {
  if (typeof URL.createObjectURL !== 'function') {
    onEnd()
    return () => {}
  }
  const url = URL.createObjectURL(new Blob([audio as BlobPart], { type: 'audio/wav' }))
  const player = new Audio(url)
  const finish = () => {
    URL.revokeObjectURL(url)
    onEnd()
  }
  player.addEventListener('ended', finish, { once: true })
  player.addEventListener('error', finish, { once: true })
  // play() can refuse (no sound device, autoplay rules); treat it as done.
  Promise.resolve(player.play()).catch(finish)
  return () => {
    player.pause()
    finish()
  }
}

/** The panel. */
export function VoicePanel() {
  const { data: settings, error, isLoading, mutate } = useVoice()
  let body
  if (isLoading) {
    body = <div className="memory__wait"><Spinner label="Asking Jarvis how he sounds…" /></div>
  } else if (error || !settings) {
    body = <p className="empty">Jarvis isn’t answering, so his voice can’t be changed right now. Open this page through Tailscale, with Jarvis running on the PC.</p>
  } else {
    body = <VoiceEditor settings={settings} onSaved={() => void mutate()} />
  }
  return (
    <section className="glass panel voice" aria-labelledby="voice-title">
      <h2 id="voice-title" className="panel__title">Voice</h2>
      <p className="panel__sub">How Jarvis sounds when he talks back. Saved on the PC, used from his next reply.</p>
      {body}
    </section>
  )
}

/** The voice list, speed, blend and Save, once Jarvis has answered. */
function VoiceEditor({ settings, onSaved }: { settings: VoiceSettings; onSaved: () => void }) {
  const voices = settings.voices
  const saved: VoiceChoice = { voice: settings.voice, speed: settings.speed, blend: settings.blend }
  const [draft, setDraft] = useState<VoiceChoice>(saved)
  const [accent, setAccent] = useState<Accent>(voices.find((v) => v.id === settings.voice)?.accent ?? 'gb')
  // Which sample is loading or playing: a voice id, or "mix" for the whole choice.
  const [sampleFor, setSampleFor] = useState<string | null>(null)
  const [sampleLoading, setSampleLoading] = useState(false)
  const [saving, setSaving] = useState(false)
  const [note, setNote] = useState('')
  const stopPlaying = useRef<(() => void) | null>(null)

  // Stop any sample when leaving the page.
  useEffect(() => () => stopPlaying.current?.(), [])

  const shown = voices.filter((v) => v.accent === accent)
  const changed = !sameChoice(draft, saved)

  /** Plays a sample of `choice`, or stops it if that one is already playing. */
  async function play(key: string, choice: VoiceChoice) {
    const wasThis = sampleFor === key
    stopPlaying.current?.()
    stopPlaying.current = null
    if (wasThis) return
    setSampleFor(key)
    setSampleLoading(true)
    setNote('')
    const sample = await fetchVoiceSample(choice)
    setSampleLoading(false)
    if (!sample.ok) {
      setSampleFor(null)
      setNote(sample.message)
      return
    }
    stopPlaying.current = playWav(sample.audio, () => {
      stopPlaying.current = null
      setSampleFor((current) => (current === key ? null : current))
    })
  }

  /** Picks the main voice, keeping the blend's second voice different from it. */
  function pick(id: string) {
    setNote('')
    setDraft((d) => {
      let blend = d.blend
      if (blend && blend.voice2 === id) blend = { ...blend, voice2: otherVoice(voices, id) }
      return { ...d, voice: id, blend }
    })
  }

  /** Turns blending on (with a similar second voice at 30%) or off. */
  function toggleBlend() {
    setNote('')
    setDraft((d) => ({ ...d, blend: d.blend ? null : { voice2: otherVoice(voices, d.voice), mix: 0.3 } }))
  }

  /** Sends the choice to Jarvis. */
  async function save() {
    setSaving(true)
    const result = await saveVoice(draft)
    setSaving(false)
    setNote(result.message)
    if (result.ok) onSaved()
  }

  const busy = saving || sampleLoading
  return (
    <>
      <div className="segmented" role="radiogroup" aria-label="Accent">
        {ACCENTS.map((a) => (
          <button key={a.id} type="button" role="radio" aria-checked={accent === a.id} className="segmented__opt" onClick={() => setAccent(a.id)}>
            {a.label}
          </button>
        ))}
      </div>

      <ul className="voice__list" aria-label="Voices">
        {shown.map((v) => (
          <li key={v.id} className="voice__row" data-picked={draft.voice === v.id ? '' : undefined}>
            <label className="voice__pick">
              <input type="radio" name="jarvis-voice" value={v.id} checked={draft.voice === v.id} onChange={() => pick(v.id)} />
              <span>
                <span className="voice__name">{v.name}</span>
                <span className="voice__kind">{voiceKind(v)}{settings.voice === v.id ? ' · current' : ''}</span>
              </span>
            </label>
            <button
              type="button"
              className="btn btn--quiet"
              aria-label={sampleFor === v.id ? `Stop ${v.name}` : `Play ${v.name}`}
              disabled={sampleLoading && sampleFor !== v.id}
              onClick={() => void play(v.id, { voice: v.id, speed: draft.speed, blend: null })}
            >
              {sampleFor === v.id ? 'Stop' : 'Play'}
            </button>
          </li>
        ))}
      </ul>

      <label className="voice__level">
        <span>Speed</span>
        <input
          type="range" min={70} max={140} step={5} value={Math.round(draft.speed * 100)}
          onChange={(e) => { setNote(''); setDraft((d) => ({ ...d, speed: Number(e.target.value) / 100 })) }}
        />
        <span className="voice__value">{speedLabel(draft.speed)}</span>
      </label>

      <button type="button" role="switch" aria-checked={draft.blend !== null} className="switch" onClick={toggleBlend}>
        <span className="switch__track" aria-hidden="true"><span className="switch__knob" /></span>
        <span>Blend in a second voice</span>
      </button>
      {draft.blend ? (
        <div className="voice__blend">
          <label className="voice__level">
            <span>With</span>
            <select
              className="jarvis__input voice__select"
              value={draft.blend.voice2}
              onChange={(e) => { const voice2 = e.target.value; setDraft((d) => (d.blend ? { ...d, blend: { ...d.blend, voice2 } } : d)) }}
            >
              {voices.filter((v) => v.id !== draft.voice).map((v) => (
                <option key={v.id} value={v.id}>{v.name} ({voiceKind(v)})</option>
              ))}
            </select>
          </label>
          <label className="voice__level">
            <span>Mix</span>
            <input
              type="range" min={10} max={90} step={5} value={Math.round(draft.blend.mix * 100)}
              aria-valuetext={mixLabel(voices, draft)}
              onChange={(e) => { const mix = Number(e.target.value) / 100; setDraft((d) => (d.blend ? { ...d, blend: { ...d.blend, mix } } : d)) }}
            />
          </label>
          <p className="voice__mix">{mixLabel(voices, draft)}</p>
        </div>
      ) : null}

      <div className="voice__actions">
        <button type="button" className="btn" disabled={sampleLoading && sampleFor !== 'mix'} onClick={() => void play('mix', draft)}>
          {sampleFor === 'mix' ? 'Stop' : 'Hear it'}
        </button>
        <button type="button" className="btn btn--primary" disabled={!changed || busy} onClick={() => void save()}>Save</button>
      </div>
      {sampleLoading ? <div className="memory__wait"><Spinner label="Making a sample…" /></div> : null}
      {saving ? <div className="memory__wait"><Spinner label="Saving…" /></div> : null}
      <p className="cloud__foot" role="status">
        {note || `Now: ${nameOf(voices, saved.voice)}${saved.blend ? ` blended with ${nameOf(voices, saved.blend.voice2)}` : ''} at ${speedLabel(saved.speed)}`}
      </p>
    </>
  )
}
