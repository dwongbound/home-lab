// The Money page: balances, this month's spending, recent transactions and
// anything worth a look, from Dylan's Copilot connector by way of the cloud
// digest (docs/digest.md). Amounts start hidden on every visit, so a glance
// at the phone doesn't show them; "Show amounts" reveals them until the page
// is reloaded.
import { createContext, useContext, useState } from 'react'
import type { MoneyAccount, MoneyDigest, Snapshot } from '../types'
import { ago, dollars } from '../lib/format'

const Hidden = createContext(true)

/** One dollar amount, or dots while amounts are hidden. */
function Amount({ value, cents = false }: { value: number; cents?: boolean }) {
  const hidden = useContext(Hidden)
  if (hidden) return <span className="money__amount" aria-label="hidden">$•••</span>
  return <span className="money__amount">{dollars(value, cents)}</span>
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
            <li key={c.name} className="cloud__row cloud__row--stack">
              <span className="money__line"><span className="cloud__title">{c.name}</span><Amount value={c.spent} /></span>
              {c.budget !== null ? <Meter spent={c.spent} limit={c.budget} /> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  )
}

/** Every account with its balance. */
function Accounts({ accounts }: { accounts: MoneyAccount[] }) {
  return (
    <section className="glass panel" aria-labelledby="accounts-title">
      <header className="panel__head"><h2 id="accounts-title" className="panel__title">Accounts</h2></header>
      {accounts.length === 0 ? <p className="empty">No accounts reported.</p> : (
        <ul className="cloud__list">
          {accounts.map((a) => (
            <li key={a.id} className="cloud__row">
              <span className="cloud__title">{a.name}<span className="cloud__meta"> · {a.institution}</span></span>
              <span className={a.kind === 'credit' || a.kind === 'loan' ? 'money__owed' : undefined}><Amount value={a.balance} cents /></span>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

/** Recent transactions, newest first. Money coming in shows as +. */
function Recent({ money, now }: { money: MoneyDigest; now: Date }) {
  return (
    <section className="glass panel" aria-labelledby="recent-title">
      <header className="panel__head"><h2 id="recent-title" className="panel__title">Recent</h2></header>
      {money.recent.length === 0 ? <p className="empty">No recent transactions.</p> : (
        <ul className="cloud__list">
          {money.recent.map((t) => (
            <li key={t.id} className="cloud__row">
              <span className="cloud__title">{t.merchant}<span className="cloud__meta"> · {t.category} · {ago(t.date, now)}</span></span>
              <span className={t.amount < 0 ? 'money__in' : undefined}>{t.amount < 0 ? '+' : ''}<Amount value={Math.abs(t.amount)} cents /></span>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

/** Things Copilot (or the digest task) thinks are worth a look. */
function Flags({ money }: { money: MoneyDigest }) {
  return (
    <section className="glass panel" aria-labelledby="flags-title">
      <header className="panel__head"><h2 id="flags-title" className="panel__title">Worth a look</h2></header>
      {money.flags.length === 0 ? <p className="empty">Nothing unusual.</p> : (
        <ul className="cloud__list">
          {money.flags.map((f) => <li key={f.id} className="cloud__row"><span className="cloud__title">{f.text}</span></li>)}
        </ul>
      )}
    </section>
  )
}

/** The Money page. */
export function Money({ data, now }: { data: Snapshot; now: Date }) {
  const [hidden, setHidden] = useState(true)
  const money = data.cloud?.money ?? null

  return (
    <Hidden.Provider value={hidden}>
      <section className="hero hero--small money__hero">
        <div>
          <h1 className="hero__title">Money</h1>
          {money !== null && data.cloud ? <p className="hero__sub">From Copilot, updated {ago(data.cloud.updatedAt, now)}.</p> : null}
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
          <div className="grid grid--split">
            <ThisMonth money={money} />
            <Accounts accounts={money.accounts} />
          </div>
          <div className="grid grid--split">
            <Recent money={money} now={now} />
            <Flags money={money} />
          </div>
        </>
      )}
    </Hidden.Provider>
  )
}
