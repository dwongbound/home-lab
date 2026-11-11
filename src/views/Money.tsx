// The Money page: balances, this month's spending, recent transactions and
// anything worth a look, from Dylan's Copilot connector by way of the cloud
// digest (docs/digest.md). Amounts start hidden on every visit, so a glance
// at the phone doesn't show them; "Show amounts" reveals them until the page
// is reloaded.
//
// Every row is a link (#money/t/x1 and so on) that opens a detail pop-up,
// so it can be bookmarked and Back closes it. Purchases still sitting in
// "Other" (or with no category) are outlined in yellow with a "!" and
// counted at the top of "Worth a look".
//
// Copilot's connector is read-only, so Dylan picks a category for each of
// those here; the picks wait on the PC (server/money-picks.mjs) in a
// "Ready for Copilot" list, grouped by category, so he can apply them all
// in Copilot in one sitting. A banner reminds him when the time he chose
// comes, and picks drop off once Copilot shows the purchase sorted.
import { createContext, useContext, useState } from 'react'
import { useSWRConfig } from 'swr'
import type { MoneyAccount, MoneyDigest, MoneyPick, MoneyPicks, MoneyTransaction, Snapshot, SpendCategory } from '../types'
import { ago, dollars } from '../lib/format'
import {
  categoryChoices, cleanText, defaultReminder, groupAccounts, groupPicks, isEmptyAccount,
  needsCategory, onAccount, picksById, reminderChoices, stillToPick,
} from '../lib/money'
import { changeMoneyPicks, SNAPSHOT_KEY } from '../api/client'
import { useDigestRefreshing } from '../api/digestRefresh'
import { closeDetail, detailHref, parseDetail, useHashDetail } from '../useHashView'
import { DetailDialog, type Fact } from '../components/DetailDialog'

const Hidden = createContext(true)
// The picks waiting for Copilot, so any row can show its picked category.
const Picks = createContext<MoneyPicks>({ picks: [], remindAt: null })

/** One dollar amount, or dots while amounts are hidden. */
function Amount({ value, cents = false }: { value: number; cents?: boolean }) {
  const hidden = useContext(Hidden)
  if (hidden) return <span className="money__amount" aria-label="hidden">$•••</span>
  return <span className="money__amount">{dollars(value, cents)}</span>
}

/** A transaction's amount: money coming in shows green with a +. */
function TxAmount({ t }: { t: MoneyTransaction }) {
  if (t.amount < 0) return <span className="money__in">+<Amount value={-t.amount} cents /></span>
  return <span><Amount value={t.amount} cents /></span>
}

/** Spent against a limit, as a thin bar (full and amber past the limit). */
function Meter({ spent, limit }: { spent: number; limit: number }) {
  const share = limit > 0 ? spent / limit : 0
  return (
    <span className="money__meter" aria-hidden="true">
      <span style={{ '--fill': Math.min(1, share) } as React.CSSProperties} data-over={share > 1 || undefined} />
    </span>
  )
}

/** Totals across accounts of one kind. */
function total(accounts: MoneyAccount[], kind: MoneyAccount['kind']): number {
  let sum = 0
  for (const a of accounts) if (a.kind === kind) sum += a.balance
  return sum
}

/** A date as "Mon, Nov 10, 3:42 PM". */
function fullDate(iso: string): string {
  return new Intl.DateTimeFormat('en-US', { weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }).format(new Date(iso))
}

/** What the page shows before Copilot data arrives, and why. */
function NotSetUp({ digestReady }: { digestReady: boolean }) {
  return (
    <section className="glass panel" aria-labelledby="money-empty-title">
      <header className="panel__head"><h2 id="money-empty-title" className="panel__title">Not connected yet</h2></header>
      <p className="empty">
        {digestReady
          ? 'Balances and spending from Copilot will show here once the digest task starts reading your Copilot connector.'
          : 'Balances and spending from Copilot will show here once the Claude digest is set up. The README’s “Cloud digest” section has the steps.'}
      </p>
    </section>
  )
}

/** The three headline numbers. */
function Totals({ money }: { money: MoneyDigest }) {
  const items = [
    { label: 'Net worth', value: money.netWorth },
    { label: 'Cash', value: total(money.accounts, 'cash') },
    { label: 'Card balances', value: total(money.accounts, 'credit') },
  ]
  return (
    <div className="grid grid--money">
      {items.map((item) => (
        <section key={item.label} className="glass panel money__total">
          <h2 className="panel__sub">{item.label}</h2>
          <p className="money__big">{item.value === null ? 'Not reported' : <Amount value={item.value} />}</p>
        </section>
      ))}
    </div>
  )
}

/** Purchases that still need a real category. */
function unsorted(money: MoneyDigest): MoneyTransaction[] {
  return money.recent.filter(needsCategory)
}

/** "One purchase" or "3 purchases". */
function purchases(n: number): string {
  if (n === 1) return 'One purchase'
  return `${n} purchases`
}

/** "Worth a look": purchases to sort first, picks waiting for Copilot, then what the digest flagged. */
function Flags({ money }: { money: MoneyDigest }) {
  const picks = useContext(Picks).picks
  const toSort = stillToPick(money.recent, picks).length
  const sortText = `${purchases(toSort)} ${toSort === 1 ? 'needs' : 'need'} a category`
  const nothing = money.flags.length === 0 && toSort === 0 && picks.length === 0
  return (
    <section className="glass panel" aria-labelledby="flags-title">
      <header className="panel__head"><h2 id="flags-title" className="panel__title">Worth a look</h2></header>
      {nothing ? <p className="empty">Nothing unusual.</p> : (
        <ul className="cloud__list">
          {picks.length > 0 ? (
            <li className="cloud__row">
              <a className="row-link row-link--ready" href={detailHref('money', 'ready')}>
                <span className="ready__mark" aria-hidden="true">✓</span>
                <span className="cloud__title">{purchases(picks.length)} ready for Copilot<span className="cloud__meta"> · apply in one go</span></span>
              </a>
            </li>
          ) : null}
          {toSort > 0 ? (
            <li className="cloud__row">
              <a className="row-link row-link--attention" href={detailHref('money', 'sort')}>
                <span className="attention__mark" aria-hidden="true">!</span>
                <span className="cloud__title">{sortText}<span className="cloud__meta"> · in Other or none</span></span>
              </a>
            </li>
          ) : null}
          {money.flags.map((f) => <li key={f.id} className="cloud__row"><span className="cloud__title">{f.text}</span></li>)}
        </ul>
      )}
    </section>
  )
}

/** Spent this month against the budget and last month, then by category. */
function ThisMonth({ money }: { money: MoneyDigest }) {
  const { thisMonth, lastMonthToDate, budget } = money.spending
  let versus = null
  if (lastMonthToDate !== null) {
    const diff = thisMonth - lastMonthToDate
    versus = <p className="panel__sub"><Amount value={Math.abs(diff)} /> {diff <= 0 ? 'less' : 'more'} than this point last month</p>
  }
  return (
    <section className="glass panel" aria-labelledby="month-title">
      <header className="panel__head">
        <div>
          <h2 id="month-title" className="panel__title">This month</h2>
          {versus}
        </div>
      </header>
      <p className="money__big"><Amount value={thisMonth} /></p>
      {budget !== null ? (
        <>
          <Meter spent={thisMonth} limit={budget} />
          <p className="cloud__foot">of <Amount value={budget} /> budgeted</p>
        </>
      ) : null}
      {money.categories.length > 0 ? (
        <ul className="cloud__list money__cats">
          {money.categories.map((c) => (
            <li key={c.name} className="cloud__row">
              <a className="row-link row-link--stack" href={detailHref('money', 'c', c.name)}>
                <span className="money__line"><span className="cloud__title">{c.name}</span><Amount value={c.spent} /></span>
                {c.budget !== null ? <Meter spent={c.spent} limit={c.budget} /> : null}
              </a>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  )
}

/** One transaction row, linked to its detail: merchant over category and when, amount on the right. Unsorted ones get the yellow "!", picked ones a ✓. */
function TxRow({ t, now }: { t: MoneyTransaction; now: Date }) {
  const pick = picksById(useContext(Picks).picks).get(t.id)
  const attention = needsCategory(t) && pick === undefined
  let className = 'row-link tx'
  let mark = null
  let category = t.category || 'No category'
  if (attention) {
    className = 'row-link tx row-link--attention'
    mark = <span className="attention__mark" aria-hidden="true">!</span>
    category = `${category}, needs a category`
  }
  if (pick !== undefined) {
    mark = <span className="ready__mark" aria-hidden="true">✓</span>
    category = `${pick.category}, to apply in Copilot`
  }
  return (
    <li className="cloud__row">
      <a className={className} href={detailHref('money', 't', t.id)}>
        {mark}
        <span className="tx__text">
          <span className="tx__merchant">{cleanText(t.merchant)}</span>
          <span className="tx__meta">{category} · {t.pending ? 'pending' : ago(t.date, now)}</span>
        </span>
        <span className="tx__amount"><TxAmount t={t} /></span>
      </a>
    </li>
  )
}

/**
 * Recent transactions, newest first. The panel is as tall as the column
 * beside it and the list scrolls inside, so a long month doesn't make the
 * page long (styles.css, .money__recent).
 */
function Recent({ money, now }: { money: MoneyDigest; now: Date }) {
  return (
    <section className="glass panel money__recent" aria-labelledby="recent-title">
      <header className="panel__head"><h2 id="recent-title" className="panel__title">Recent</h2></header>
      {money.recent.length === 0 ? <p className="empty">No recent transactions.</p> : (
        <div className="money__scroll" tabIndex={0} aria-label="Recent transactions">
          <ul className="cloud__list">
            {money.recent.map((t) => <TxRow key={t.id} t={t} now={now} />)}
          </ul>
        </div>
      )}
    </section>
  )
}

/** One account row, linked to its detail. */
function AccountRow({ a }: { a: MoneyAccount }) {
  let owed: string | undefined
  if (a.kind === 'credit' || a.kind === 'loan') owed = 'money__owed'
  return (
    <li className="cloud__row">
      <a className="row-link" href={detailHref('money', 'a', a.id)}>
        <span className="cloud__title">{cleanText(a.name)}<span className="cloud__meta"> · {cleanText(a.institution)}</span></span>
        <span className={owed}><Amount value={a.balance} cents /></span>
      </a>
    </li>
  )
}

/** Accounts grouped by kind with a subtotal each. Empty ($0) ones wait behind a button. */
function Accounts({ accounts }: { accounts: MoneyAccount[] }) {
  const [showEmpty, setShowEmpty] = useState(false)
  const empties = accounts.filter(isEmptyAccount).length
  let shown = accounts
  if (!showEmpty) shown = accounts.filter((a) => !isEmptyAccount(a))
  const groups = groupAccounts(shown)
  let toggle = `Show ${empties} empty accounts`
  if (empties === 1) toggle = 'Show 1 empty account'
  if (showEmpty) toggle = 'Hide empty accounts'
  return (
    <section className="glass panel" aria-labelledby="accounts-title">
      <header className="panel__head"><h2 id="accounts-title" className="panel__title">Accounts</h2></header>
      {groups.length === 0 ? <p className="empty">No accounts with money in them.</p> : groups.map((g) => (
        <div key={g.kind} className="cloud__group">
          <h3 className="cloud__label money__line"><span>{g.label}</span><Amount value={g.total} /></h3>
          <ul className="cloud__list">
            {g.accounts.map((a) => <AccountRow key={a.id} a={a} />)}
          </ul>
        </div>
      ))}
      {empties > 0 ? (
        <button type="button" className="btn btn--quiet money__empties" aria-expanded={showEmpty} onClick={() => setShowEmpty((s) => !s)}>{toggle}</button>
      ) : null}
    </section>
  )
}

/** A short list of transactions inside a detail pop-up, each linked to its own. */
function TxList({ items, now, empty }: { items: MoneyTransaction[]; now: Date; empty: string }) {
  if (items.length === 0) return <p className="empty">{empty}</p>
  return <ul className="cloud__list detail__list">{items.map((t) => <TxRow key={t.id} t={t} now={now} />)}</ul>
}

/**
 * Saves a change to the picks, then refetches the snapshot so every row
 * shows it. `busy` holds a label while it's saving (shown as a blocking
 * status); `error` holds what went wrong.
 */
function usePickChange() {
  const { mutate } = useSWRConfig()
  const [busy, setBusy] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  /** Sends one change; true when it was saved. */
  async function run(label: string, change: Parameters<typeof changeMoneyPicks>[0]): Promise<boolean> {
    setBusy(label)
    setError(null)
    try {
      const result = await changeMoneyPicks(change)
      await mutate(SNAPSHOT_KEY)
      if (!result.ok) setError(result.message)
      return result.ok
    } finally {
      setBusy(null)
    }
  }
  return { busy, error, run }
}

/** "Saving…" over a panel while a change is on its way to the PC. */
function Saving({ label }: { label: string | null }) {
  if (label === null) return null
  return <p className="money__saving" role="status">{label}</p>
}

/**
 * Picking a category for one unsorted purchase. Copilot's connector is
 * read-only, so the pick waits on the PC for the "Ready for Copilot" list.
 */
function CategoryPicker({ t, choices }: { t: MoneyTransaction; choices: string[] }) {
  const pick = picksById(useContext(Picks).picks).get(t.id)
  const [other, setOther] = useState('')
  const { busy, error, run } = usePickChange()

  /** Saves `category` for this purchase. The first pick also sets tomorrow evening's reminder. */
  async function choose(category: string) {
    const ok = await run('Saving…', {
      op: 'pick', id: t.id, category, merchant: cleanText(t.merchant), date: t.date, amount: t.amount,
      remindAt: defaultReminder(new Date()).toISOString(),
    })
    if (ok) setOther('')
  }

  let hint = 'Pick a category. It waits here until you apply it in Copilot, with the rest, from “Ready for Copilot”.'
  if (pick !== undefined) hint = `Saved as ${pick.category}. Apply it in Copilot from “Ready for Copilot”; it clears once Copilot shows it sorted.`
  return (
    <div className="picker" aria-busy={busy !== null}>
      <p className="detail__hint">{hint}</p>
      <div className="picker__chips" role="group" aria-label="Category">
        {choices.map((c) => (
          <button key={c} type="button" className="btn picker__chip" aria-pressed={pick?.category === c} disabled={busy !== null} onClick={() => choose(c)}>{c}</button>
        ))}
      </div>
      <form className="picker__other" onSubmit={(e) => { e.preventDefault(); if (other.trim()) choose(other.trim()) }}>
        <input className="picker__input" value={other} onChange={(e) => setOther(e.target.value)} placeholder="Another category" aria-label="Another category" maxLength={60} disabled={busy !== null} />
        <button type="submit" className="btn" disabled={busy !== null || other.trim() === ''}>Save</button>
      </form>
      {pick !== undefined ? (
        <button type="button" className="btn btn--quiet picker__undo" disabled={busy !== null} onClick={() => run('Removing…', { op: 'clear', ids: [t.id] })}>Remove pick</button>
      ) : null}
      <Saving label={busy} />
      {error ? <p className="money__error" role="alert">{error}</p> : null}
    </div>
  )
}

/** The pop-up for one transaction. */
function TransactionDetail({ t, now, choices }: { t: MoneyTransaction; now: Date; choices: string[] }) {
  const facts: Fact[] = [
    { label: 'Amount', value: <TxAmount t={t} /> },
    { label: 'When', value: t.pending ? `${fullDate(t.date)} (pending)` : fullDate(t.date) },
    { label: 'Category', value: t.category || 'None' },
  ]
  if (t.account) facts.push({ label: 'Account', value: cleanText(t.account) })
  if (t.note) facts.push({ label: 'Note', value: cleanText(t.note) })
  let sub = `${t.category || 'No category'} · ${ago(t.date, now)}`
  if (needsCategory(t)) sub = 'Needs a category'
  return (
    <DetailDialog title={cleanText(t.merchant)} sub={sub} facts={facts} onClose={closeDetail}>
      {needsCategory(t) ? <CategoryPicker t={t} choices={choices} /> : null}
    </DetailDialog>
  )
}

/** The pop-up for one account: its balance and its recent transactions. */
function AccountDetail({ a, money, now }: { a: MoneyAccount; money: MoneyDigest; now: Date }) {
  let balanceLabel = 'Balance'
  if (a.kind === 'credit' || a.kind === 'loan') balanceLabel = 'Owed'
  const facts: Fact[] = [
    { label: balanceLabel, value: <Amount value={a.balance} cents /> },
    { label: 'Bank', value: cleanText(a.institution) },
  ]
  return (
    <DetailDialog title={cleanText(a.name)} sub={cleanText(a.institution)} facts={facts} onClose={closeDetail}>
      <h3 className="cloud__label">Recent on this account</h3>
      <TxList items={onAccount(money.recent, a)} now={now} empty="Nothing recent on this account in the digest." />
    </DetailDialog>
  )
}

/** The pop-up for one spending category: against its budget, and what went in it. */
function CategoryDetail({ c, money, now }: { c: SpendCategory; money: MoneyDigest; now: Date }) {
  const facts: Fact[] = [{ label: 'Spent', value: <Amount value={c.spent} /> }]
  if (c.budget !== null) {
    facts.push({ label: 'Budget', value: <Amount value={c.budget} /> })
    const left = c.budget - c.spent
    facts.push({ label: left >= 0 ? 'Left' : 'Over by', value: <Amount value={Math.abs(left)} /> })
  }
  const items = money.recent.filter((t) => t.category === c.name)
  return (
    <DetailDialog title={c.name} sub="This month" facts={facts} onClose={closeDetail}>
      {c.budget !== null ? <Meter spent={c.spent} limit={c.budget} /> : null}
      <h3 className="cloud__label">Recent in {c.name}</h3>
      <TxList items={items} now={now} empty="Nothing recent in this category in the digest." />
    </DetailDialog>
  )
}

/** The pop-up listing every purchase still needing a category; tap one to pick. */
function SortDetail({ money, now }: { money: MoneyDigest; now: Date }) {
  const items = unsorted(money)
  const picked = useContext(Picks).picks.length
  return (
    <DetailDialog title="Needs a category" sub={`${items.length} recent purchases in Other or none`} onClose={closeDetail}>
      <p className="detail__hint">Tap a purchase to pick its category. Copilot can’t be changed from here, so picks wait in “Ready for Copilot” for you to apply in one go.</p>
      {picked > 0 ? <a className="btn btn--wide picker__ready" href={detailHref('money', 'ready')}>Ready for Copilot ({picked})</a> : null}
      <TxList items={items} now={now} empty="All sorted." />
    </DetailDialog>
  )
}

/** A date as "Mon, Nov 10". */
function shortDate(iso: string): string {
  if (!iso) return ''
  return new Intl.DateTimeFormat('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).format(new Date(iso))
}

/** One pick in the Ready list, with Done once it's applied in Copilot. */
function ReadyRow({ p, onDone, busy }: { p: MoneyPick; onDone: () => void; busy: boolean }) {
  return (
    <li className="cloud__row ready__row">
      <span className="tx__text">
        <span className="tx__merchant">{p.merchant || 'Purchase'}</span>
        <span className="tx__meta">{shortDate(p.date)}</span>
      </span>
      <span className="tx__amount"><Amount value={p.amount} cents /></span>
      <button type="button" className="btn btn--quiet ready__done" disabled={busy} onClick={onDone} aria-label={`Done: ${p.merchant}`}>Done</button>
    </li>
  )
}

/** When the reminder goes off, and buttons to move it. */
function Reminder({ remindAt, now, run, busy }: { remindAt: string | null; now: Date; run: ReturnType<typeof usePickChange>['run']; busy: boolean }) {
  let when = 'No reminder set.'
  if (remindAt !== null) {
    const at = new Date(remindAt)
    if (at.getTime() <= now.getTime()) when = 'Reminding you now.'
    else when = `Reminding you ${fullDate(remindAt)}.`
  }
  return (
    <div className="ready__remind">
      <p className="panel__sub">{when}</p>
      <div className="picker__chips" role="group" aria-label="Remind me">
        {reminderChoices(now).map((c) => (
          <button key={c.label} type="button" className="btn btn--quiet" disabled={busy} onClick={() => run('Moving the reminder…', { op: 'remind', at: c.at.toISOString() })}>{c.label}</button>
        ))}
      </div>
    </div>
  )
}

/** Everything picked, grouped by category, to apply in Copilot in one sitting. */
function ReadyDetail({ now }: { now: Date }) {
  const { picks, remindAt } = useContext(Picks)
  const { busy, error, run } = usePickChange()
  const groups = groupPicks(picks)
  return (
    <DetailDialog title="Ready for Copilot" sub={`${purchases(picks.length)} to recategorize`} onClose={closeDetail}>
      {picks.length === 0 ? <p className="empty">Nothing waiting. Pick categories from “Needs a category”.</p> : (
        <>
          <p className="detail__hint">In Copilot, set each purchase below to its category, then tap Done (or All done). Ones Copilot already shows sorted clear by themselves.</p>
          {groups.map((g) => (
            <div key={g.category} className="cloud__group">
              <h3 className="cloud__label money__line"><span>{g.category}</span><span>{g.picks.length}</span></h3>
              <ul className="cloud__list">
                {g.picks.map((p) => <ReadyRow key={p.id} p={p} busy={busy !== null} onDone={() => run('Clearing…', { op: 'clear', ids: [p.id] })} />)}
              </ul>
            </div>
          ))}
          <button type="button" className="btn btn--wide" disabled={busy !== null} onClick={() => run('Clearing…', { op: 'clear', ids: picks.map((p) => p.id) })}>All done in Copilot</button>
          <Reminder remindAt={remindAt} now={now} run={run} busy={busy !== null} />
        </>
      )}
      <Saving label={busy} />
      {error ? <p className="money__error" role="alert">{error}</p> : null}
    </DetailDialog>
  )
}

/** Whichever detail the hash names, or nothing. An unknown id shows nothing. */
function MoneyDetail({ money, now }: { money: MoneyDigest; now: Date }) {
  const detail = useHashDetail()
  const picks = useContext(Picks)
  if (detail === '') return null
  const { kind, id } = parseDetail(detail)
  // Keyed by the detail, so moving from one to another reopens the dialog fresh.
  if (kind === 'sort') return <SortDetail key={detail} money={money} now={now} />
  if (kind === 'ready') return <ReadyDetail key={detail} now={now} />
  if (kind === 't') {
    const t = money.recent.find((x) => x.id === id)
    const choices = categoryChoices(money.categories.map((c) => c.name), picks.picks)
    if (t) return <TransactionDetail key={detail} t={t} now={now} choices={choices} />
  }
  if (kind === 'a') {
    const a = money.accounts.find((x) => x.id === id)
    if (a) return <AccountDetail key={detail} a={a} money={money} now={now} />
  }
  if (kind === 'c') {
    const c = money.categories.find((x) => x.name === id)
    if (c) return <CategoryDetail key={detail} c={c} money={money} now={now} />
  }
  return null
}

/** The Money page. */
export function Money({ data, now }: { data: Snapshot; now: Date }) {
  const [hidden, setHidden] = useState(true)
  const money = data.cloud?.money ?? null
  const refreshing = useDigestRefreshing()

  return (
    <Hidden.Provider value={hidden}>
    <Picks.Provider value={data.moneyPicks}>
      <section className="hero hero--small money__hero">
        <div>
          <h1 className="hero__title">Money</h1>
          {money !== null && data.cloud ? (
            <p className="hero__sub">
              From Copilot, updated {ago(data.cloud.updatedAt, now)}.
              {refreshing ? <span className="updating" role="status"> Updating from Jarvis…</span> : null}
            </p>
          ) : null}
        </div>
        {money !== null ? (
          <button type="button" className="btn" aria-pressed={!hidden} onClick={() => setHidden((h) => !h)}>
            {hidden ? 'Show amounts' : 'Hide amounts'}
          </button>
        ) : null}
      </section>
      {money === null ? <NotSetUp digestReady={data.cloud !== null} /> : (
        <>
          <Totals money={money} />
          {/* Left: what needs a look, this month and accounts. Right: recent
              transactions, as tall as the left side and scrolling inside.
              One column on phones, with Recent capped and scrolling. */}
          <div className="grid grid--split money__split">
            <div className="stack">
              <Flags money={money} />
              <ThisMonth money={money} />
              <Accounts accounts={money.accounts} />
            </div>
            <div className="money__side">
              <Recent money={money} now={now} />
            </div>
          </div>
          <MoneyDetail money={money} now={now} />
        </>
      )}
    </Picks.Provider>
    </Hidden.Provider>
  )
}
