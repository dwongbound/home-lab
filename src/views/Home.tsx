import { useCallback, useState } from 'react'
import { useSWRConfig } from 'swr'
import type { HomeDevice, HomeRequest, Snapshot } from '../types'
import { controlHome, SNAPSHOT_KEY } from '../api/client'
import { BUSY_LABEL, DeviceGroup, SceneRow } from '../components/HomeDevices'
import { ConfirmDialog } from '../components/ConfirmDialog'

// The Home page: control the house through Home Assistant. Scenes first,
// then lights, climate, doors, TVs and speakers, and plugs and fans. Unlocking a door or
// opening a cover asks first; everything else happens on one tap.

/** Commands that open the house up, so they get a confirm dialog. */
function needsConfirm(request: HomeRequest): boolean {
  return request.command === 'unlock' || request.command === 'open'
}

/** "2 lights on · Front door locked · 68° inside", or a plain line when there's nothing to say. */
export function homeSummary(devices: HomeDevice[]): string {
  const parts: string[] = []
  let lightsOn = 0
  for (const d of devices) if (d.kind === 'light' && d.on) lightsOn++
  if (lightsOn === 0) parts.push('All lights off')
  else if (lightsOn === 1) parts.push('1 light on')
  else parts.push(`${lightsOn} lights on`)

  const unlocked = devices.filter((d) => d.kind === 'lock' && !d.unavailable && !d.on)
  if (unlocked.length > 0) parts.push(`${unlocked[0].name} unlocked`)
  const open = devices.filter((d) => d.kind === 'cover' && d.on)
  if (open.length > 0) parts.push(`${open[0].name} open`)

  const climate = devices.find((d) => d.kind === 'climate' && d.temperature !== null)
  if (climate) parts.push(`${climate.temperature}° inside`)
  return parts.join(' · ')
}

/** What the page shows when there are no devices to control. */
function NoDevices({ connected }: { connected: boolean }) {
  return (
    <section className="glass panel note">
      <h2 className="panel__title">{connected ? 'No devices yet' : 'Home Assistant isn’t connected'}</h2>
      {connected
        ? <p>Add your devices in Home Assistant under Settings → Devices &amp; services. Most brands have their own integration, and they show up here on the next refresh.</p>
        : <p>The page reads your devices from Home Assistant with the <code>HA_TOKEN</code> in the server’s <code>.env</code>. Check that Home Assistant is running and the token is set.</p>}
    </section>
  )
}

interface Pending { device: HomeDevice; request: HomeRequest }

/** The Home page. */
export function Home({ data, onToast }: { data: Snapshot; onToast: (m: string) => void }) {
  const { mutate } = useSWRConfig()
  // Spinner labels for the devices HA is working on, by entity id.
  const [busy, setBusy] = useState<Record<string, string>>({})
  // An unlock or open waiting for the confirm dialog.
  const [pending, setPending] = useState<Pending | null>(null)
  const [dialogBusy, setDialogBusy] = useState(false)
  const [dialogError, setDialogError] = useState<string | null>(null)

  /** Sends one command, refetches the snapshot, and says how it went. Returns the error, if any. */
  const run = useCallback(async (device: HomeDevice, request: HomeRequest): Promise<string | null> => {
    setBusy((b) => ({ ...b, [device.id]: BUSY_LABEL[request.command] }))
    let error: string | null = null
    try {
      const result = await controlHome(request)
      // Refetch either way: a failed command can still have changed things.
      await mutate(SNAPSHOT_KEY)
      if (result.ok) onToast(`${device.name} ${result.message}`)
      else error = result.message
    } catch (e) {
      error = e instanceof Error ? e.message : 'The request failed'
    } finally {
      setBusy((b) => {
        const next = { ...b }
        delete next[device.id]
        return next
      })
    }
    return error
  }, [mutate, onToast])

  /** A tile asked for something: confirm first if it opens the house, else just do it. */
  const send = useCallback((device: HomeDevice, request: HomeRequest) => {
    if (needsConfirm(request)) {
      setDialogError(null)
      setPending({ device, request })
      return
    }
    void run(device, request).then((error) => {
      if (error !== null) onToast(`Couldn’t change ${device.name}: ${error}`)
    })
  }, [run, onToast])

  /** The confirm dialog's button: run it, close on success, keep the error otherwise. */
  async function confirm() {
    if (pending === null) return
    setDialogBusy(true)
    const error = await run(pending.device, pending.request)
    setDialogBusy(false)
    if (error === null) setPending(null)
    else setDialogError(error)
  }

  const devices = data.home ?? []
  const ofKind = (...kinds: HomeDevice['kind'][]) => devices.filter((d) => kinds.includes(d.kind))
  const climate = ofKind('climate')
  const doors = ofKind('lock', 'cover')
  const unlocking = pending?.request.command === 'unlock'

  return (
    <>
      <section className="hero hero--small">
        <h1 className="hero__title">Home</h1>
        {devices.length > 0 ? <p className="hero__sub">{homeSummary(devices)}</p> : null}
      </section>
      {devices.length === 0 ? <NoDevices connected={data.home !== null} /> : null}
      <SceneRow scenes={ofKind('scene')} busy={busy} onSend={send} />
      <DeviceGroup title="Lights" devices={ofKind('light')} busy={busy} onSend={send} />
      {/* Climate and doors share a row only when both have something in them. */}
      {climate.length > 0 && doors.length > 0 ? (
        <div className="grid grid--split">
          <DeviceGroup title="Climate" devices={climate} busy={busy} onSend={send} />
          <DeviceGroup title="Doors" devices={doors} busy={busy} onSend={send} />
        </div>
      ) : (
        <>
          <DeviceGroup title="Climate" devices={climate} busy={busy} onSend={send} />
          <DeviceGroup title="Doors" devices={doors} busy={busy} onSend={send} />
        </>
      )}
      <DeviceGroup title="TV and speakers" devices={ofKind('media')} busy={busy} onSend={send} />
      <DeviceGroup title="Plugs and fans" devices={ofKind('switch', 'fan')} busy={busy} onSend={send} />
      {pending !== null ? (
        <ConfirmDialog
          title={unlocking ? `Unlock ${pending.device.name}?` : `Open ${pending.device.name}?`}
          body={unlocking ? 'Anyone at the door will be able to walk in.' : 'It will open now, wherever you are.'}
          confirmLabel={unlocking ? 'Unlock' : 'Open'}
          busyLabel={BUSY_LABEL[pending.request.command]}
          busy={dialogBusy}
          error={dialogError}
          onConfirm={confirm}
          onClose={() => setPending(null)}
        />
      ) : null}
    </>
  )
}
