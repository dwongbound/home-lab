// User stories, on desktop and phone:
//   - I open the page and see how jarvis is doing.
//   - Once it has loaded, nothing on it shifts (no shake as data and fonts arrive).
//   - Panels below the screen fade in as I scroll down to them, and nothing replays once it has landed.
//   - I move between Overview, Services, Schedule and Settings, and it glides.
//   - I unload the local model before gaming, and see it working until it's done.
//   - I pick a sky in Settings and it's remembered.
//   - The first load simply appears (no landing show); with reduced motion on, nothing moves.
//   - I tap any money row, Today row, event or email for a pop-up with more, and links out.
//   - Purchases still in "Other" stand out so I know to sort them.
//   - The iPad can stay on as a wall display, with the whole Overview on one screen.
//   - Kiosk mode (top right) goes full screen and moves through the tabs by itself; Money shows only purchases there.
//   - I swipe sideways to change tab.
//   - In Safari, changing tab never shows the panels dark before they frost.
//   - I ask Jarvis from the Overview and the chat types out his answer; Talk goes hands-free.
//   - /talk is just the chat, full screen: one tap on Talk and I'm talking; Close goes to the dashboard.
//   - Before Jarvis writes a file, runs a command or changes his own code, the chat asks me, and I tap Approve or Deny (or say yes, no or wait).
//   - While the chat is open the page behind it stays put, and reading back up isn't interrupted by new words.
//   - In Settings, under Voice, I play a sample, pick a voice, speed and blend, and save it.
//   - In Settings, under Memory, I see what Jarvis remembers, teach him something, forget it, and search past chats.
import { expect, test } from '@playwright/test'

test('overview shows the PC at a glance', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Dylan')
  for (const label of ['Memory', 'GPU memory', 'Processor', 'Free on C:']) {
    await expect(page.getByRole('heading', { name: label, exact: true })).toBeVisible()
  }
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'Today', exact: true })).toBeVisible()
  // Kept to a glance: the chart, services and the model live on their own pages.
  await expect(page.getByRole('heading', { name: 'Jarvis requests' })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Unload local model' })).toHaveCount(0)
})

test('nothing on the Overview shifts after it loads, even when the chat history is slow', async ({ page, browserName }) => {
  // Only Chromium reports layout shifts.
  test.skip(browserName !== 'chromium', 'layout-shift entries are Chromium-only')
  await page.addInitScript(() => {
    const w = window as unknown as { shifts: number }
    w.shifts = 0
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) w.shifts += (entry as unknown as { value: number }).value
    }).observe({ type: 'layout-shift', buffered: true })
  })
  // The history arriving late is what used to push every panel down.
  await page.route('**/api/jarvis/history', async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 600))
    await route.continue()
  })
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  await page.waitForTimeout(2500)
  const shifts = await page.evaluate(() => (window as unknown as { shifts: number }).shifts)
  expect(shifts).toBeLessThan(0.005)
})

test('once the page has landed nothing animates again, and lower panels fade in as I scroll to them', async ({ page }) => {
  await page.addInitScript(() => {
    const w = window as unknown as { late: string[] }
    w.late = []
    // Anything starting after the landing (~2.6 s) while the page sits still
    // is the "shake" that used to drop the lower panels back down.
    document.addEventListener('animationstart', (e) => {
      if (performance.now() > 2000) w.late.push(`${e.animationName} on ${(e.target as Element).className}`)
    }, true)
  })
  // A short window, so Services runs past the bottom on every device.
  await page.setViewportSize({ width: page.viewportSize()!.width, height: 560 })
  await page.goto('/#services')
  await page.waitForTimeout(3500)
  expect(await page.evaluate(() => (window as unknown as { late: string[] }).late)).toEqual([])

  // Its last panel waits, hidden, until reached.
  const last = page.locator('.main .glass').last()
  await expect(last).toHaveAttribute('data-reveal', 'wait')
  await expect.poll(() => last.evaluate((el) => getComputedStyle(el.firstElementChild!).opacity)).toBe('0')
  await last.scrollIntoViewIfNeeded()
  await expect(last).toHaveAttribute('data-reveal', 'in')
  await expect.poll(() => last.evaluate((el) => getComputedStyle(el.firstElementChild!).opacity)).toBe('1')
  // Panels on screen at load faded in with the page and are fully there.
  const first = page.locator('.main .glass').first()
  await expect(first).toHaveAttribute('data-reveal', 'in')
  expect(await first.evaluate((el) => getComputedStyle(el.firstElementChild!).opacity)).toBe('1')
})

test('an alert is a banner across the top, not a row in Today, and Close hides it', async ({ page }) => {
  await page.goto('/')
  // The sample Jarvis is degraded.
  const banner = page.getByRole('alert')
  await expect(banner).toContainText('Jarvis: Running, code changed since start')
  await expect(page.locator('.timeline')).not.toContainText('code changed since start')
  await expect(banner.getByRole('link')).toHaveAttribute('href', '#services')
  // It follows to every page.
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Money' }).click()
  await expect(page.getByRole('alert')).toBeVisible()
  await page.getByRole('alert').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('alert')).toHaveCount(0)
})

test('opening the page asks Jarvis for a fresh digest, showing the last one meanwhile', async ({ page }) => {
  await page.goto('/#schedule')
  const calendar = page.locator('section', { has: page.getByRole('heading', { name: 'Calendar' }) })
  await expect(calendar.getByText('Updating from Jarvis…')).toBeVisible()
  // The last digest stays on screen while Jarvis works.
  await expect(calendar.getByText('Flight block N8318B')).toBeVisible()
  // The sample refresh takes 4 s; the page looks every 5 s.
  await expect(calendar.getByText('Updating from Jarvis…')).toHaveCount(0, { timeout: 15_000 })
  await expect(calendar.getByText('Updated just now')).toBeVisible()
})

test('Schedule has the requests chart; Services has every service, the model card, what is loaded, Jarvis’s jobs and a terminal', async ({ page }) => {
  await page.goto('/#schedule')
  await expect(page.getByRole('heading', { name: 'Jarvis requests' })).toBeVisible()
  await page.goto('/#services')
  await expect(page.getByRole('link', { name: 'Open Home Assistant' })).toHaveAttribute('href', 'http://192.168.68.94:8123')
  await expect(page.getByRole('button', { name: 'Unload local model' })).toBeVisible()
  const loaded = page.getByRole('region', { name: 'In GPU memory' })
  await expect(loaded).toContainText('ornith-1.5:9b')
  await expect(loaded).toContainText('answers when Claude can’t be reached')
  // What Jarvis runs in the background: the three main jobs and the housekeeping.
  const jobs = page.getByRole('region', { name: 'What Jarvis is doing' })
  await jobs.scrollIntoViewIfNeeded()
  for (const name of ['Lookout', 'Messenger', 'Nightly', 'Quiet housekeeping', 'Decided not to bother you with']) {
    await expect(jobs.getByText(name, { exact: true })).toBeVisible()
  }
  await expect(jobs).toContainText('pings sent today')
  // The terminal replaced the "Restarting Jarvis" note.
  await expect(page.locator('iframe[title="Terminal on jarvis"]')).toBeVisible()
  await expect(page.getByText('Restarting Jarvis')).toHaveCount(0)
})

test('tapping a tab fades the new page in and slides the pill light, with no motion at all with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const context = await browser.newContext({ reducedMotion })
    const page = await context.newPage()
    await page.goto(test.info().project.use.baseURL + '/')
    await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
    const nav = page.getByRole('navigation', { name: 'Sections' })
    await nav.getByRole('link', { name: 'Services' }).click()
    await expect(page.getByRole('heading', { level: 1, name: 'Services' })).toBeVisible()
    // The new page's panels fade their contents in (never the glass itself, which stays frosted).
    const first = page.locator('.main .glass').first()
    if (reducedMotion === 'reduce') {
      expect(await page.evaluate(() => document.documentElement.dataset.enter ?? 'none')).toBe('none')
      await expect(first).not.toHaveAttribute('data-reveal', /.+/)
    } else {
      await expect(first).toHaveAttribute('data-reveal', 'in')
      expect(await first.evaluate((el) => getComputedStyle(el).backdropFilter)).toContain('blur(26px)')
      await expect.poll(() => first.evaluate((el) => getComputedStyle(el.firstElementChild!).opacity)).toBe('1')
    }
    // One light, sitting under the current pill once it settles.
    await expect(nav.locator('.pills__light')).toHaveCount(1)
    const current = await nav.getByRole('link', { name: 'Services' }).boundingBox()
    // Within a pixel: the bar's 1 px border and subpixel layout can round either way.
    await expect.poll(async () => Math.abs((await nav.locator('.pills__light').boundingBox())!.x - current!.x)).toBeLessThanOrEqual(1.5)
    await context.close()
  }
})

test('pill navigation reaches every page and keeps the back button working', async ({ page }) => {
  await page.goto('/')
  const nav = page.getByRole('navigation', { name: 'Sections' })
  for (const name of ['Home', 'Money', 'Services', 'Schedule', 'Settings']) {
    await nav.getByRole('link', { name }).click()
    await expect(page.getByRole('heading', { level: 1, name })).toBeVisible()
    await expect(nav.getByRole('link', { name })).toHaveAttribute('aria-current', 'page')
  }
  await page.goBack()
  await expect(page.getByRole('heading', { level: 1, name: 'Schedule' })).toBeVisible()
})

test('unloading the local model blocks the dialog until it finishes, then loading it back works', async ({ page }) => {
  await page.goto('/#services')
  await page.getByRole('button', { name: 'Unload local model' }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('Unload the local model?')
  await expect(dialog.getByRole('button', { name: 'Close' })).toBeVisible()

  await dialog.getByRole('button', { name: 'Unload', exact: true }).click()
  await expect(dialog.getByText('Unloading the local model…')).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Close' })).toBeDisabled()

  await expect(page.getByRole('status').filter({ hasText: 'Local model unloaded' })).toBeVisible()
  await expect(page.getByText('Unloaded', { exact: true })).toBeVisible()
  // Nothing is left in GPU memory, and the list says how it comes back.
  await expect(page.getByRole('region', { name: 'In GPU memory' })).toContainText('No model is loaded')

  // Put it back so the next test starts from the same state.
  await page.getByRole('button', { name: 'Load local model' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Load', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Unload local model' })).toBeVisible({ timeout: 10_000 })
})

test('Close dismisses the dialog with Esc or the button', async ({ page }) => {
  await page.goto('/#services')
  await page.getByRole('button', { name: 'Unload local model' }).click()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await page.getByRole('button', { name: 'Unload local model' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
})

test('the sky choice is remembered across reloads', async ({ page }) => {
  await page.goto('/#preferences')
  await page.getByRole('radio', { name: 'Night' }).click()
  await expect(page.locator('.backdrop')).toHaveAttribute('data-phase', 'night')
  await page.reload()
  await expect(page.getByRole('radio', { name: 'Night' })).toHaveAttribute('aria-checked', 'true')
  await expect(page.locator('.backdrop')).toHaveAttribute('data-phase', 'night')
})

test('nothing animates with reduced motion', async ({ browser }) => {
  const context = await browser.newContext({ reducedMotion: 'reduce' })
  const page = await context.newPage()
  await page.goto(test.info().project.use.baseURL + '/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const running = await page.evaluate(() => document.getAnimations().length)
  expect(running).toBe(0)
  await context.close()
})

test('no sideways scrolling', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
})

test('the Claude page shows threads waiting on me first, linked to the thread', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Claude' }).click()
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  const threads = page.getByRole('region', { name: 'Claude threads' })
  await expect(threads.getByRole('heading', { level: 3 }).first()).toHaveText(/Waiting on you/)
  await expect(threads.getByRole('link', { name: 'Fix unverified app warning on calendar picker' })).toHaveAttribute('target', '_blank')
  await expect(page.getByRole('region', { name: 'Shipping' })).toContainText('tapworship.com')
})

test('the first load fades the panels in, one after another, then nothing moves and the glass stays frosted', async ({ page }) => {
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  // No landing show on the frame itself: only what's inside the glass fades.
  await expect(page.locator('[data-landing]')).toHaveCount(0)
  const first = page.locator('.main .glass').first()
  await expect(first).toHaveAttribute('data-reveal', 'in')
  // Once the fade is over nothing keeps running (an endless loop inside glass
  // made the iPhone redraw its blur every frame, which quivered).
  await expect.poll(() => page.evaluate(() => document.getAnimations().filter((a) => a.playState === 'running').map((a) => (a as CSSAnimation).animationName).filter((n) => n && !/think|spin|caret/.test(n))), { timeout: 5000 }).toEqual([])
  const blur = await first.evaluate((el) => getComputedStyle(el).backdropFilter)
  expect(blur).toContain('blur(26px)')
})

test('the thermostat shows the room temperature, and + and the mode buttons change it', async ({ page }) => {
  await page.goto('/#home')
  const tile = page.getByRole('region', { name: 'Thermostat' })
  await expect(tile).toBeVisible()
  await expect(tile.getByText('Inside')).toBeVisible()
  // It says when it's working: in Heat with the room (68°) below the setting.
  await expect(tile.locator('.thermo__status')).toHaveText(/^Heating to \d+°$/)
  await expect(tile).toHaveAttribute('data-activity', 'heating')
  // The thermostat comes first on the page.
  await expect(page.locator('.home > .thermo').first()).toHaveAttribute('aria-label', 'Thermostat')
  const target = tile.locator('.thermo__target')
  const before = Number((await target.textContent())!.replace(/\D/g, ''))
  // Two quick taps send one command, for two steps.
  const sent = page.waitForRequest((r) => r.url().endsWith('/api/home/control'))
  await tile.getByRole('button', { name: 'Warmer' }).click()
  await tile.getByRole('button', { name: 'Warmer' }).click()
  await expect(target).toContainText(`${before + 2}°`)
  expect((await sent).postDataJSON()).toEqual({ entity: 'climate.thermostat', command: 'target', value: before + 2 })
  // Back down, and modes are buttons that show which one is on.
  await tile.getByRole('button', { name: 'Cooler' }).click()
  await tile.getByRole('button', { name: 'Cooler' }).click()
  const heat = tile.getByRole('group', { name: 'Mode' }).getByRole('button', { name: 'Heat', exact: true })
  await expect(heat).toHaveAttribute('aria-pressed', 'true')
  const box = (await heat.boundingBox())!
  expect(box.height).toBeGreaterThanOrEqual(44)
})

test('Services has the terminal, and there is no separate Shell tab', async ({ page }) => {
  await page.goto('/#services')
  await expect(page.getByRole('heading', { level: 1, name: 'Services' })).toBeVisible()
  await expect(page.getByRole('navigation', { name: 'Sections' }).getByRole('link', { name: 'Shell' })).toHaveCount(0)
  // The test server has no SHELL_USERS, so the frame explains instead of opening a terminal.
  const frame = page.frameLocator('iframe[title="Terminal on jarvis"]')
  await expect(frame.getByText('The shell is off')).toBeVisible()
  await expect(page.getByRole('link', { name: 'Open the terminal full screen' })).toHaveAttribute('href', './shell/')
  // An old #shell link lands on the Overview.
  await page.goto('/#shell')
  await expect(page.getByRole('heading', { level: 1 })).toContainText('Dylan')
})

test('the terminal key bar sends Ctrl+C, pastes in and copies out', async ({ page, context, browserName }) => {
  // A stand-in for ttyd: a page whose window.term records what it's sent.
  await page.route('**/shell/', (route) => route.fulfill({
    contentType: 'text/html',
    body: `<!doctype html><body><script>
      window.sent = [];
      const lines = ['$ ls', 'notes.txt', ''];
      window.term = {
        input: (d) => window.sent.push(['key', d]),
        paste: (t) => window.sent.push(['paste', t]),
        focus: () => {},
        hasSelection: () => false,
        getSelection: () => '',
        rows: 3,
        buffer: { active: { viewportY: 0, length: 3, getLine: (y) => ({ translateToString: () => lines[y] }) } },
      };
    </script></body>`,
  }))
  if (browserName === 'chromium') await context.grantPermissions(['clipboard-read', 'clipboard-write'])
  await page.goto('/#services')
  const bar = page.getByRole('toolbar', { name: 'Terminal keys' })
  await expect(bar).toBeVisible()
  const sent = () => page.frame({ url: /\/shell\/$/ })!.evaluate(() => (window as unknown as { sent: [string, string][] }).sent)

  // Ctrl+C goes in as a key press (an interrupt), not as pasted text.
  const ctrlC = bar.getByRole('button', { name: 'Send Ctrl+C' })
  expect((await ctrlC.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await ctrlC.click()
  await expect.poll(sent).toEqual([['key', '\x03']])

  // Paste: the system clipboard where the browser shares it, else a box to paste into.
  await bar.getByRole('button', { name: 'Paste' }).click()
  const box = page.getByRole('dialog', { name: 'Paste into the terminal' })
  const pasted = page.getByRole('status').filter({ hasText: 'Pasted.' })
  await expect(box.or(pasted)).toBeVisible()
  if (await box.isVisible()) {
    const field = box.getByRole('textbox')
    expect(await field.evaluate((el) => getComputedStyle(el).fontSize)).toBe('16px')
    await field.fill('echo hi')
    await box.getByRole('button', { name: 'Send' }).click()
    await expect(box).toBeHidden()
    await expect.poll(sent).toEqual([['key', '\x03'], ['paste', 'echo hi']])
  }

  // Copy: the screen goes to the clipboard, or shows in a box to copy by hand.
  await bar.getByRole('button', { name: 'Copy' }).click()
  const copyBox = page.getByRole('dialog', { name: 'Copy from the terminal' })
  const copied = page.getByRole('status').filter({ hasText: 'Copied the screen.' })
  await expect(copyBox.or(copied)).toBeVisible()
  if (await copyBox.isVisible()) {
    await expect(copyBox.getByRole('textbox')).toHaveValue('$ ls\nnotes.txt')
    await copyBox.getByRole('button', { name: 'Close' }).click()
  } else {
    if (browserName === 'chromium') expect(await page.evaluate(() => navigator.clipboard.readText())).toBe('$ ls\nnotes.txt')
  }
})

test('Money flags purchases to sort, and every row opens a detail that Close and Back dismiss', async ({ page }) => {
  await page.goto('/#money')
  await expect(page.getByRole('heading', { level: 1, name: 'Money' })).toBeVisible()
  // The "undefined" from Venmo is gone, and the row is marked to sort.
  const venmo = page.getByRole('link', { name: /Venmo Alex/ })
  await expect(venmo).not.toContainText('undefined')
  await expect(venmo).toContainText('needs a category')
  // $0 accounts wait behind a button.
  await expect(page.getByText('Old Checking')).toHaveCount(0)

  await page.getByRole('link', { name: /2 purchases need a category/ }).click()
  const dialog = page.getByRole('dialog', { name: 'Needs a category' })
  await expect(dialog).toBeVisible()
  // From the list, straight into the purchase.
  await dialog.getByRole('link', { name: /Venmo Alex/ }).click()
  await expect(page.getByRole('dialog', { name: 'Venmo Alex' })).toContainText('Lesson')
  await page.getByRole('dialog').getByRole('button', { name: 'Close' }).click()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page).toHaveURL(/#money$/)

  // An account shows what's been on it; Back closes the pop-up.
  await page.getByRole('link', { name: /Sapphire/ }).click()
  await expect(page.getByRole('dialog', { name: 'Sapphire' })).toContainText('Trader Joe’s')
  await page.goBack()
  await expect(page.getByRole('dialog')).toHaveCount(0)
  await expect(page.getByRole('heading', { level: 1, name: 'Money' })).toBeVisible()
})

test('Money: pick categories for unsorted purchases, then clear them from Ready for Copilot', async ({ page }) => {
  await page.goto('/#money/t/x6')
  const amazon = page.getByRole('dialog', { name: 'Amazon' })
  await amazon.getByRole('button', { name: 'Shopping' }).click()
  await expect(amazon.getByRole('button', { name: 'Shopping' })).toHaveAttribute('aria-pressed', 'true')
  await expect(amazon).toContainText('Saved as Shopping')
  await amazon.getByRole('button', { name: 'Close' }).click()

  // A category of his own, typed in.
  await page.goto('/#money/t/x5')
  const venmo = page.getByRole('dialog', { name: 'Venmo Alex' })
  await venmo.getByRole('textbox', { name: 'Another category' }).fill('Golf lessons')
  await venmo.getByRole('button', { name: 'Save' }).click()
  await expect(venmo).toContainText('Saved as Golf lessons')
  await venmo.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: /2 purchases ready for Copilot/ }).click()
  const ready = page.getByRole('dialog', { name: 'Ready for Copilot' })
  await expect(ready.getByRole('heading', { name: /Golf lessons/ })).toBeVisible()
  await expect(ready.getByRole('heading', { name: /Shopping/ })).toBeVisible()
  await expect(ready).toContainText('Reminding you')
  await ready.getByRole('button', { name: 'Done: Amazon' }).click()
  await expect(ready.getByRole('button', { name: 'Done: Amazon' })).toHaveCount(0)
  await ready.getByRole('button', { name: 'All done in Copilot' }).click()
  await expect(ready).toContainText('Nothing waiting')
})

test('Money: Recent is as tall as the left column and scrolls inside', async ({ page }, testInfo) => {
  await page.goto('/#money')
  const recent = page.locator('.money__recent')
  await expect(recent).toBeVisible()
  const box = await recent.boundingBox()
  const left = await page.locator('.money__split > .stack').boundingBox()
  if (!box || !left) throw new Error('no layout')
  if (testInfo.project.name === 'phone') {
    // One column: Recent comes after the left column, capped at 60% of the screen.
    expect(box.y).toBeGreaterThan(left.y + left.height - 1)
    const cap = await page.evaluate(() => window.innerHeight * 0.6)
    const list = await page.locator('.money__scroll').boundingBox()
    expect(list!.height).toBeLessThanOrEqual(cap + 1)
  } else {
    expect(Math.abs(box.height - left.height)).toBeLessThanOrEqual(2)
    expect(Math.abs(box.y - left.y)).toBeLessThanOrEqual(2)
  }
  const overflow = await page.locator('.money__scroll').evaluate((el) => getComputedStyle(el).overflowY)
  expect(overflow).toBe('auto')
})

test('the detail pop-up fits the screen and stays one size', async ({ page }) => {
  await page.goto('/#money/sort')
  const dialog = page.getByRole('dialog', { name: 'Needs a category' })
  await expect(dialog).toBeVisible()
  const box = (await dialog.boundingBox())!
  const view = page.viewportSize()!
  expect(box.width).toBeLessThanOrEqual(view.width - 31)
  expect(box.height).toBeLessThanOrEqual(view.height - 31)
  await page.goto('/#money/t/x4')
  const other = (await page.getByRole('dialog', { name: 'Spotify' }).boundingBox())!
  expect(Math.round(other.height)).toBe(Math.round(box.height))
})

test('Today and calendar rows open their details, with a link to Google Calendar', async ({ page }) => {
  await page.goto('/#schedule')
  await page.locator('section', { has: page.getByRole('heading', { name: 'Calendar' }) }).getByRole('link', { name: /Flight block N8318B/ }).click()
  const dialog = page.getByRole('dialog', { name: 'Flight block N8318B' })
  await expect(dialog).toContainText('Santa Monica Airport')
  await expect(dialog.getByRole('link', { name: 'Open in Calendar' })).toHaveAttribute('target', '_blank')
  await dialog.getByRole('button', { name: 'Close' }).click()

  await page.getByRole('link', { name: /OAuth verification/ }).click()
  await expect(page.getByRole('dialog').getByRole('link', { name: 'Open in Gmail' })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await page.goto('/')
  await page.locator('.timeline').getByRole('link').first().click()
  await expect(page.getByRole('dialog')).toBeVisible()
})

test('Settings can keep the screen on, and remembers it', async ({ page }) => {
  await page.goto('/#preferences')
  const awake = page.getByRole('switch', { name: 'Keep the screen on' })
  await expect(awake).toHaveAttribute('aria-checked', 'false')
  await awake.click()
  await expect(awake).toHaveAttribute('aria-checked', 'true')
  await expect(page.getByRole('status').filter({ hasText: /^On\./ })).toBeVisible()
  await page.reload()
  await expect(page.getByRole('switch', { name: 'Keep the screen on' })).toHaveAttribute('aria-checked', 'true')
})

test('every page fits without sideways scrolling, and tappable rows are finger-sized on touch', async ({ page }, info) => {
  for (const hash of ['#money', '#schedule', '#home', '#preferences', '#claude']) {
    await page.goto('/' + hash)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
    expect(overflow, hash).toBeLessThanOrEqual(0)
  }
  if (info.project.name === 'desktop') return
  // No text box under 16px, or the iPhone zooms in when one is tapped.
  for (const hash of ['', '#money', '#home', '#preferences']) {
    await page.goto('/' + hash)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    const sizes = await page.locator('input:not([type=radio]):not([type=checkbox]), textarea, select').evaluateAll((els) => els.map((el) => parseFloat(getComputedStyle(el).fontSize)))
    expect(Math.min(16, ...sizes), hash || 'overview').toBeGreaterThanOrEqual(16)
  }
  await page.goto('/#money')
  const heights = await page.locator('.row-link').evaluateAll((els) => els.map((el) => el.getBoundingClientRect().height))
  expect(Math.min(...heights)).toBeGreaterThanOrEqual(44)
  // The tabs, the top bar's buttons and the Claude thread links too.
  await page.goto('/#claude')
  await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
  const sizes = await page.locator('.pill, .topbar .icon-btn, .cloud__title[href]').evaluateAll((els) =>
    els.map((el) => { const r = el.getBoundingClientRect(); return { h: r.height, w: r.width, name: el.textContent } }))
  for (const s of sizes) expect(Math.min(s.h, s.w), s.name ?? '').toBeGreaterThanOrEqual(44)
})

/** Swipes across the page with one finger, from (x1, y) to (x2, y). */
async function swipe(page: import('@playwright/test').Page, x1: number, x2: number, y: number) {
  await page.evaluate(([a, b, yy]) => {
    const target = document.elementFromPoint(a, yy) ?? document.body
    const touch = (x: number) => new Touch({ identifier: 1, target, clientX: x, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [touch(a)], changedTouches: [touch(a)] }))
    target.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [touch(b)] }))
  }, [x1, x2, y])
}

/** Puts one finger down at (x1, y) and drags it to (x2, y) without lifting it. */
async function dragFinger(page: import('@playwright/test').Page, x1: number, x2: number, y: number) {
  await page.evaluate(([a, b, yy]) => {
    const target = document.elementFromPoint(a, yy) ?? document.body
    const touch = (x: number) => new Touch({ identifier: 1, target, clientX: x, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [touch(a)], changedTouches: [touch(a)] }))
    for (let i = 1; i <= 8; i++) {
      const x = a + ((b - a) * i) / 8
      target.dispatchEvent(new TouchEvent('touchmove', { bubbles: true, touches: [touch(x)], changedTouches: [touch(x)] }))
    }
  }, [x1, x2, y])
}

/** Lifts the finger at (x, y). */
async function liftFinger(page: import('@playwright/test').Page, x: number, y: number) {
  await page.evaluate(([xx, yy]) => {
    const target = document.elementFromPoint(xx, yy) ?? document.body
    const touch = new Touch({ identifier: 1, target, clientX: xx, clientY: yy })
    target.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [], changedTouches: [touch] }))
  }, [x, y])
}

test('while swiping, the page follows the finger, and springs back from a short swipe', async ({ page }, info) => {
  test.skip(info.project.name === 'desktop', 'Swiping is for touch screens')
  await page.goto('/#home')
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  const { width, height } = page.viewportSize()!
  const y = Math.round(height * 0.6)
  const title = page.locator('.main .hero').first()
  const shift = () => title.evaluate((el) => new DOMMatrix(getComputedStyle(el).transform).m41 + (parseFloat(getComputedStyle(el).translate.split(' ')[0]) || 0))
  // Finger halfway across a short way: the title and whole panels move with it.
  await dragFinger(page, Math.round(width * 0.6), Math.round(width * 0.6) - 50, y)
  expect(await shift()).toBeLessThan(-10)
  const panel = page.locator('.main .glass').first()
  expect(parseFloat(await panel.evaluate((el) => getComputedStyle(el).translate))).toBeLessThan(-10)
  // Still frosted while it moves.
  expect(await panel.evaluate((el) => getComputedStyle(el).backdropFilter)).toContain('blur(')
  // Too short to count: it springs back and stays on Home.
  await liftFinger(page, Math.round(width * 0.6) - 50, y)
  await expect.poll(() => page.locator('main.main').getAttribute('data-swipe')).toBeNull()
  expect(Math.abs(await shift())).toBeLessThan(1)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // A long slow drag counts: the contents glide out and the next tab glides in.
  await dragFinger(page, Math.round(width * 0.8), Math.round(width * 0.3), y)
  await liftFinger(page, Math.round(width * 0.3), y)
  await expect(page.locator('main.main')).toHaveAttribute('data-swipe', 'leave')
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  await expect.poll(() => page.evaluate(() => document.documentElement.dataset.enter ?? 'done')).toBe('done')
  expect(await page.locator('main.main').getAttribute('data-swipe')).toBeNull()
})

test('on the iPad the whole Overview fits the screen with no scrolling', async ({ page }, info) => {
  test.skip(info.project.name === 'phone', 'A phone scrolls the Overview')
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const extra = await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight)
  expect(extra).toBeLessThanOrEqual(0)
  // Today and the Claude threads are on screen, not pushed below it.
  for (const name of ['Today', 'Claude threads']) {
    const box = (await page.getByRole('heading', { name, exact: true }).boundingBox())!
    expect(box.y + box.height).toBeLessThan(page.viewportSize()!.height)
  }
})

test('the iPad held upright fits the Overview too', async ({ browser }) => {
  const context = await browser.newContext({ viewport: { width: 834, height: 1194 }, hasTouch: true, isMobile: true })
  const page = await context.newPage()
  await page.goto(test.info().project.use.baseURL + '/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  const extra = await page.evaluate(() => document.documentElement.scrollHeight - window.innerHeight)
  expect(extra).toBeLessThanOrEqual(0)
  await context.close()
})

test('swiping sideways changes tab, and not inside a text box', async ({ page }, info) => {
  test.skip(info.project.name === 'desktop', 'Swiping is for touch screens')
  await page.goto('/#home')
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  const { width, height } = page.viewportSize()!
  const y = Math.round(height * 0.6)
  // Finger moving left: the next tab.
  await swipe(page, Math.round(width * 0.7), Math.round(width * 0.25), y)
  await expect(page.getByRole('heading', { level: 1, name: 'Claude' })).toBeVisible()
  // Moving right: back again.
  await swipe(page, Math.round(width * 0.25), Math.round(width * 0.7), y)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // A short nudge isn't a swipe.
  await swipe(page, Math.round(width * 0.5), Math.round(width * 0.5) - 30, y)
  await expect(page.getByRole('heading', { level: 1, name: 'Home' })).toBeVisible()
  // Nor is a drag in the Ask Jarvis box.
  await page.goto('/')
  const input = (await page.getByRole('textbox', { name: 'Question for Jarvis' }).boundingBox())!
  await swipe(page, input.x + input.width * 0.8, input.x + 10, input.y + input.height / 2)
  await expect(page.getByRole('heading', { level: 1, name: /Dylan/ })).toBeVisible()
})

test('while the first snapshot is on its way, a full-page "Jarvis is thinking" loader shows, still with reduced motion', async ({ browser }) => {
  for (const reducedMotion of ['no-preference', 'reduce'] as const) {
    const context = await browser.newContext({ reducedMotion })
    const page = await context.newPage()
    // Hold the first snapshot back so the loader can be seen.
    let release = () => {}
    const held = new Promise<void>((resolve) => { release = resolve })
    await page.route('**/api/snapshot', async (route) => { await held; await route.continue() })
    await page.goto(test.info().project.use.baseURL + '/')
    const loader = page.getByRole('status').filter({ hasText: 'Jarvis is thinking' })
    await expect(loader).toBeVisible()
    const moving = await page.evaluate(() => document.getAnimations().filter((a) => (a.effect as KeyframeEffect | null)?.target instanceof Element && ((a.effect as KeyframeEffect).target as Element).closest('.thinking')).length)
    if (reducedMotion === 'reduce') expect(moving).toBe(0)
    else expect(moving).toBeGreaterThan(3)
    release()
    await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
    await expect(loader).toHaveCount(0)
    await context.close()
  }
})

test('before Jarvis runs a command the chat asks, and Approve or Deny decides it', async ({ page }) => {
  test.setTimeout(45_000)
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('Please restart Jarvis')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  // The card shows exactly what he wants to run, and he waits.
  const card = chat.getByRole('group', { name: 'Jarvis asks: Run a command' }).last()
  await expect(card).toBeVisible({ timeout: 10_000 })
  await expect(card.getByText('sudo systemctl restart jarvis')).toBeVisible()
  // Opening the chat doesn't put a focus ring on ×.
  await expect(chat.getByRole('button', { name: 'Close', exact: true })).not.toBeFocused()
  // A focused text box gets a brighter edge, never the blue ring.
  expect(await chat.getByRole('textbox', { name: 'Message Jarvis' }).evaluate((el) => { el.focus(); return getComputedStyle(el).outlineStyle })).toBe('none')
  await expect(chat.getByRole('status')).toHaveText('Waiting for your OK')
  // Finger-sized buttons.
  const approve = card.getByRole('button', { name: 'Approve' })
  expect((await approve.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await approve.click()
  // Settled, it shrinks to one line in the history.
  await expect(chat.getByText(/^Approved: /).last()).toBeVisible()
  await expect(card).toBeHidden()
  await expect(chat.getByText('Sample data: done. Jarvis restarted.').last()).toBeVisible({ timeout: 10_000 })

  // Deny leaves it alone.
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk', { timeout: 10_000 })
  await chat.getByRole('textbox', { name: 'Message Jarvis' }).fill('Edit my todo note')
  await chat.getByRole('button', { name: 'Send' }).click()
  const edit = chat.getByRole('group', { name: 'Jarvis asks: Edit a file' }).last()
  await expect(edit).toBeVisible({ timeout: 10_000 })
  await edit.getByRole('button', { name: 'Deny' }).click()
  await expect(chat.getByText(/^Denied: /).last()).toBeVisible()
  await expect(chat.getByText('Sample data: okay, I left it alone.').last()).toBeVisible({ timeout: 10_000 })

  // Changing himself: one plain question, and the answer shows in the card.
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk', { timeout: 10_000 })
  await chat.getByRole('textbox', { name: 'Message Jarvis' }).fill('Change your code so drive times mention parking')
  await chat.getByRole('button', { name: 'Send' }).click()
  const change = chat.getByRole('group', { name: 'Jarvis asks: Change Jarvis’s code' }).last()
  await expect(change).toBeVisible({ timeout: 10_000 })
  await expect(change.getByText('Is it OK if I change my code so drive times mention parking?')).toBeVisible()
  await change.getByRole('button', { name: 'Approve' }).click()
  await expect(chat.getByText('Approved: Is it OK if I change my code so drive times mention parking?').last()).toBeVisible()
  await expect(chat.getByText(/Starting that now/).last()).toBeVisible({ timeout: 10_000 })
  // Everything fits inside the sheet, Talk included, even on a narrow phone.
  const sheet = (await chat.boundingBox())!
  const talk = (await chat.getByRole('button', { name: 'Talk', exact: true }).boundingBox())!
  expect(talk.x + talk.width).toBeLessThanOrEqual(sheet.x + sheet.width)
  await chat.getByRole('button', { name: 'Close', exact: true }).click()
})

test('the page behind the chat stays put, and scrolling up to read back is not pulled down by new words', async ({ page }) => {
  test.setTimeout(60_000)
  // A shorter window on desktop so a few turns are enough to make the chat scroll.
  const size = page.viewportSize()!
  if (size.height > 700) await page.setViewportSize({ width: size.width, height: 520 })
  await page.goto('/')
  const before = await page.evaluate(() => { window.scrollTo(0, 120); return window.scrollY })
  // Enough turns that the chat scrolls.
  const bar = page.getByRole('textbox', { name: 'Question for Jarvis' })
  await bar.fill('Is the garage open?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  const box = chat.getByRole('textbox', { name: 'Message Jarvis' })
  for (const q of ['What is on today?', 'How is the weather for flying?', 'Any email I should read?']) {
    await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk', { timeout: 10_000 })
    await box.fill(q)
    await chat.getByRole('button', { name: 'Send' }).click()
  }
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk', { timeout: 10_000 })

  // The page behind is pinned: its body doesn't scroll while the chat is open.
  expect(await page.evaluate(() => getComputedStyle(document.body).position)).toBe('fixed')

  // Talk, then scroll up to read back while the demo turn plays.
  await chat.getByRole('button', { name: 'Talk', exact: true }).click()
  await expect(chat.getByRole('status')).toHaveText('Listening… just talk')
  const list = chat.getByRole('list')
  await list.evaluate((el) => { el.scrollTop = 0; el.dispatchEvent(new Event('scroll')) })
  await expect(chat.getByText(/you have volleyball at 7:30/).last()).toBeAttached({ timeout: 15_000 })
  expect(await list.evaluate((el) => el.scrollTop)).toBeLessThan(40)
  // Latest takes him back down.
  await chat.getByRole('button', { name: /Latest/ }).click()
  expect(await list.evaluate((el) => el.scrollHeight - el.scrollTop - el.clientHeight)).toBeLessThan(50)

  await chat.getByRole('button', { name: 'Stop talking' }).click()
  await chat.getByRole('button', { name: 'Close', exact: true }).click()
  await expect(chat).toHaveCount(0)
  // Back where the page was.
  expect(await page.evaluate(() => getComputedStyle(document.body).position)).not.toBe('fixed')
  expect(await page.evaluate(() => window.scrollY)).toBe(before)
})

test('leaving the page while Jarvis thinks: the reply still shows up when I come back', async ({ page }) => {
  // The phone drops the reply stream ("Load failed"); Jarvis finishes at home and saves the answer.
  const question = `Move Disneyland to Dec 8 (${Date.now()})`
  let saved = false
  await page.route('**/api/jarvis/chat', (route) => { saved = true; return route.abort('failed') })
  await page.route('**/api/jarvis/history', (route) => route.fulfill({
    json: { turns: saved ? [
      { role: 'user', text: question, at: new Date().toISOString() },
      { role: 'jarvis', text: 'Moved Disneyland to Monday, Dec 8.', at: new Date().toISOString() },
    ] : [] },
  }))
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill(question)
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  await expect(chat.getByText('Moved Disneyland to Monday, Dec 8.')).toBeVisible({ timeout: 15_000 })
  await expect(chat.getByText('Load failed')).toHaveCount(0)
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk')
})

test('Jarvis offers tasks he noticed: Hide drops one, Start opens the chat and gets going', async ({ page }) => {
  // Answered here so the shared sample server keeps its offers for the other devices.
  let hidden: unknown = null
  let started: unknown = null
  await page.route('**/api/jarvis/offers/hide', async (route) => { hidden = route.request().postDataJSON(); await route.fulfill({ json: { ok: true, message: 'Hidden' } }) })
  await page.route('**/api/jarvis/chat', async (route) => {
    started = route.request().postDataJSON()
    await route.fulfill({ contentType: 'application/x-ndjson', body: '{"type":"delta","text":"Here’s a draft for Alex."}\n{"type":"done","ok":true}\n' })
  })
  await page.goto('/')
  // His line for the moment, without a second hello under "Good evening, Dylan".
  await expect(page.locator('.hero__sub')).toContainText('Your 7 PM practice moved to court 2.')
  // Folded into one bar with a count, closed until he opens it.
  const toggle = page.getByRole('button', { name: /Tasks I could help with/ })
  await expect(toggle).toHaveAttribute('aria-expanded', 'false')
  await expect(toggle.locator('.offers__count')).toHaveText("2")
  expect((await toggle.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await expect(page.getByRole('button', { name: 'Start: Find a cover for your Sunday bass slot' })).toBeHidden()
  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-expanded', 'true')
  await page.getByRole('button', { name: 'Hide: Book the oil change before your Thursday flight' }).click()
  await expect(page.getByText('Book the oil change before your Thursday flight')).toHaveCount(0)
  expect(hidden).toEqual({ id: 'o-oil' })
  await expect(toggle.locator('.offers__count')).toHaveText("1")
  const start = page.getByRole('button', { name: 'Start: Find a cover for your Sunday bass slot' })
  expect((await start.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await start.click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  await expect(chat.getByText('Here’s a draft for Alex.')).toBeVisible()
  expect(started).toEqual({ text: 'Yes, draft the note asking Alex to cover bass on Sunday.', offerId: 'o-cover' })
})

test('asking Jarvis opens the chat, and Talk goes hands-free until Stop talking', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('Is the garage open?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  // The sample server keeps the chat across tests, so look at the newest reply.
  await expect(chat.getByText('Jarvis would answer "Is the garage open?" here.', { exact: false }).last()).toBeVisible({ timeout: 10_000 })
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk')

  // Sample data has no Jarvis to talk to, so Talk plays the demo turn.
  await chat.getByRole('button', { name: 'Talk', exact: true }).click()
  await expect(chat.getByRole('status')).toHaveText('Listening… just talk')
  // One line along the bottom: Stop talking takes Send's place, and there's no read-aloud switch.
  await expect(chat.getByRole('button', { name: 'Send' })).toHaveCount(0)
  await expect(chat.getByRole('button', { name: 'Stop talking' })).toBeVisible()
  await expect(chat.getByRole('switch')).toHaveCount(0)
  // Talk mode fills the width of the screen.
  const viewport = page.viewportSize()!
  const box = (await chat.boundingBox())!
  expect(box.width).toBeGreaterThan(viewport.width - 40)
  await expect(chat.getByText(/you have volleyball at 7:30/).last()).toBeVisible({ timeout: 15_000 })
  await chat.getByRole('button', { name: 'Stop talking' }).click()
  await expect(chat.getByRole('button', { name: 'Talk', exact: true })).toBeEnabled({ timeout: 10_000 })
  await chat.getByRole('button', { name: 'Close', exact: true }).click()
  await expect(chat).toHaveCount(0)
})

test('Settings Memory shows what Jarvis remembers; I teach him something, forget it, and search past chats', async ({ page }) => {
  await page.goto('/#preferences')
  const panel = page.getByRole('region', { name: 'Memory' })
  await expect(panel.getByRole('list', { name: 'Things Jarvis remembers' })).toBeVisible()

  // Teach him something with a name unique to this run (the sample server is shared).
  const fact = `Likes test fact ${Date.now()}`
  await panel.getByRole('textbox', { name: 'Something for Jarvis to remember' }).fill(fact)
  await panel.getByRole('button', { name: 'Remember' }).click()
  await expect(panel.getByText(fact)).toBeVisible()

  // Forget asks first, with Close to back out.
  await panel.getByRole('button', { name: `Forget: ${fact}` }).click()
  const confirm = page.getByRole('dialog', { name: 'Forget this?' })
  await confirm.getByRole('button', { name: 'Forget', exact: true }).click()
  await expect(panel.getByText(fact)).toHaveCount(0)

  await panel.getByRole('searchbox', { name: 'Search past conversations' }).fill('big light')
  await panel.getByRole('button', { name: 'Search', exact: true }).click()
  await expect(panel.getByRole('list', { name: 'Search results' }).getByText('The big light is on at 60 percent.')).toBeVisible()
})

test('Settings Voice plays a sample, and saves a voice, speed and blend', async ({ page }) => {
  await page.goto('/#preferences')
  const panel = page.getByRole('region', { name: 'Voice' })
  const voices = panel.getByRole('list', { name: 'Voices' })
  // Other runs may have saved an American voice, which opens that list.
  const accent = panel.getByRole('radiogroup', { name: 'Accent' })
  await accent.getByRole('radio', { name: 'British' }).click()
  await expect(voices.getByRole('radio', { name: /George/ })).toBeVisible()

  await panel.getByRole('button', { name: 'Play Lewis' }).click()
  await expect(panel.getByRole('button', { name: /Play Lewis|Stop Lewis/ })).toBeVisible()

  // The sample server is shared, so flip between two voices to always make a change.
  await accent.getByRole('radio', { name: 'American' }).click()
  const bella = voices.getByRole('radio', { name: /Bella/ })
  const pick = (await bella.isChecked()) ? 'Heart' : 'Bella'
  await voices.getByRole('radio', { name: new RegExp(pick) }).check()
  await panel.getByRole('slider', { name: /Speed/ }).fill('115')
  await expect(panel.getByText('1.15×', { exact: true })).toBeVisible()
  const blend = panel.getByRole('switch', { name: 'Blend in a second voice' })
  if ((await blend.getAttribute('aria-checked')) !== 'true') await blend.click()
  await expect(panel.getByText(new RegExp(`% ${pick} · \\d+% `))).toBeVisible()
  await panel.getByRole('button', { name: 'Save' }).click()
  await expect(panel.getByText(/^Saved\. /)).toBeVisible()
  await expect(panel.getByRole('button', { name: 'Save' })).toBeDisabled()
})

test('the page uses the whole width of a big screen, with no empty bands at the sides', async ({ page }) => {
  await page.setViewportSize({ width: 1920, height: 1080 })
  await page.goto('/')
  const shell = (await page.locator('.shell').boundingBox())!
  expect(shell.x).toBe(0)
  // All of it, less a scroll bar at most (it used to stop at 1440 px).
  expect(shell.width).toBeGreaterThanOrEqual(1920 - 20)
})

test('/talk is voice only, edge to edge and already talking: no typing, no Close, Mute beside the button that pauses and resumes', async ({ page }) => {
  await page.goto('/talk')
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  await expect(chat).toBeVisible()
  // No dashboard around it: no tabs, no Ask Jarvis bar.
  await expect(page.getByRole('navigation')).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toHaveCount(0)
  // Not a pop-up: it is the whole screen, edge to edge, with no card edge or corners.
  const viewport = page.viewportSize()!
  const box = (await chat.boundingBox())!
  expect(box).toEqual({ x: 0, y: 0, width: viewport.width, height: viewport.height })
  const look = await chat.evaluate((el) => {
    const css = getComputedStyle(el)
    return { radius: css.borderTopLeftRadius, border: css.borderTopWidth, blur: css.backdropFilter }
  })
  expect(look).toEqual({ radius: '0px', border: '0px', blur: 'none' })
  // The sky behind it reaches the bottom of the screen too.
  const sky = (await page.locator('.backdrop').boundingBox())!
  expect(sky.y + sky.height).toBeGreaterThanOrEqual(viewport.height)
  // The orb follows the screen: 12% of its short side, 40 to 160 px (small on a phone, big on a TV),
  // with nothing written over it (the "Jarvis" title went 2026-11-16).
  const orbBox = (await chat.locator('.chat__head .orb').boundingBox())!
  const expected = Math.min(160, Math.max(40, Math.min(viewport.width, viewport.height) * 0.12))
  expect(Math.abs(orbBox.width - expected)).toBeLessThan(1.5)
  await expect(chat.getByRole('heading', { name: 'Jarvis' })).toHaveCount(0)
  // Work he sent to the background sits in the empty space right of the orb, each with a spinner,
  // the next one marked "Up next". The orb stays centred.
  const tasks = chat.getByRole('list', { name: 'Working on in the background' })
  await expect(tasks.getByRole('listitem')).toHaveCount(2)
  await expect(tasks.getByText('Making drive times mention parking')).toBeVisible()
  await expect(tasks.getByText('Up next')).toBeVisible()
  const tasksBox = (await tasks.boundingBox())!
  expect(tasksBox.x).toBeGreaterThanOrEqual(orbBox.x + orbBox.width)
  expect(tasksBox.x + tasksBox.width).toBeLessThanOrEqual(viewport.width)
  expect(Math.abs(orbBox.x + orbBox.width / 2 - viewport.width / 2)).toBeLessThan(2)
  // Each job also lights a dark amber dot on the orb. Tapping it (it rides on a turning dot, hence
  // force) opens a note with what the work is and how long it has run; Close shuts it.
  const workDot = chat.getByRole('button', { name: 'Jarvis is working: Making drive times mention parking' })
  expect((await workDot.boundingBox())!.width).toBeGreaterThanOrEqual(44)
  await workDot.click({ force: true })
  const note = chat.locator('.orb__note')
  await expect(note).toContainText('Making drive times mention parking')
  await expect(note).toContainText(/Running for \d+ min|Just started/)
  const noteBox = (await note.boundingBox())!
  expect(noteBox.x).toBeGreaterThanOrEqual(0)
  expect(noteBox.x + noteBox.width).toBeLessThanOrEqual(viewport.width)
  const closeNote = note.getByRole('button', { name: 'Close' })
  expect((await closeNote.boundingBox())!.height).toBeGreaterThanOrEqual(44)
  await closeNote.click()
  await expect(note).toHaveCount(0)
  // Words fade out under the orb instead of a hard edge.
  const mask = await chat.locator('.chat__turns').evaluate((el) => getComputedStyle(el).maskImage || getComputedStyle(el).webkitMaskImage)
  expect(mask).toContain('linear-gradient')
  // Saved to the home screen it opens straight here.
  await expect(page.locator('link[rel="manifest"]')).toHaveAttribute('href', './talk.webmanifest')
  const manifest = await (await page.request.get('/talk.webmanifest')).json()
  expect(manifest.start_url).toBe('./talk')
  // iOS reads the app from the HTML as served, before any script, so /talk's own head must name it.
  const served = await (await page.request.get('/talk')).text()
  expect(served).toContain('href="./talk.webmanifest"')
  expect(served).toContain('content="Talk"')

  // Voice only, and nothing to close: nowhere to type, nothing to send, no ×.
  await expect(chat.getByRole('textbox')).toHaveCount(0)
  await expect(chat.getByRole('button', { name: 'Send' })).toHaveCount(0)
  await expect(chat.getByRole('button', { name: 'Close' })).toHaveCount(0)
  await page.keyboard.press('Escape')
  await expect(chat).toBeVisible()

  // Talking already (sample data plays the demo, which needs no tap).
  await expect(chat.getByRole('button', { name: 'Pause', exact: true })).toBeVisible()
  // Just the orb: it shows listening, thinking and speaking, so the status line is for screen readers only.
  await expect(chat.getByRole('heading', { name: 'Jarvis' })).toHaveCount(0)
  expect((await chat.getByRole('status').boundingBox())!.height).toBeLessThanOrEqual(1)
  // Mute stops only the microphone: Talk carries on, and the status says so.
  const mute = chat.getByRole('button', { name: 'Mute', exact: true })
  await expect(mute).toHaveAttribute('aria-pressed', 'false')
  const muteBox = (await mute.boundingBox())!
  expect(muteBox.height).toBeGreaterThanOrEqual(44)
  await mute.click()
  const unmute = chat.getByRole('button', { name: 'Unmute', exact: true })
  await expect(unmute).toHaveAttribute('aria-pressed', 'true')
  await expect(chat.getByRole('status')).toHaveText('Muted. Jarvis can still talk.')
  await expect(chat.getByRole('button', { name: 'Pause', exact: true })).toBeVisible()
  await unmute.click()
  await expect(chat.getByRole('button', { name: 'Mute', exact: true })).toBeVisible()
  // The same button pauses, and tapping it again picks back up.
  await chat.getByRole('button', { name: 'Pause', exact: true }).click()
  await expect(chat.getByRole('button', { name: 'Talk', exact: true })).toBeEnabled({ timeout: 10_000 })
  await expect(chat.getByRole('status')).toHaveText('Tap Talk to start')
  await chat.getByRole('button', { name: 'Talk', exact: true }).click()
  await expect(chat.getByRole('status')).toHaveText('Listening… just talk')
  await chat.getByRole('button', { name: 'Pause', exact: true }).click()
  await expect(chat.getByRole('button', { name: 'Talk', exact: true })).toBeEnabled({ timeout: 10_000 })
  // Still the whole screen after talking stops.
  expect((await chat.boundingBox())!.width).toBe(viewport.width)
})

test('kiosk mode goes full screen, moves through the tabs by itself, and Close leaves it', async ({ page, browserName }) => {
  // A fake clock, so the 20 s on each tab passes at once.
  await page.clock.install()
  await page.goto('/')
  await expect(page.getByRole('heading', { name: 'Ask Jarvis' })).toBeVisible()
  await page.getByRole('button', { name: 'Kiosk mode' }).click()
  const close = page.getByRole('button', { name: 'Close kiosk mode' })
  await expect(close).toBeVisible()
  await expect(page.getByRole('button', { name: 'Refresh now' })).toHaveCount(0)
  // Chromium allows full screen from the tap. (iPhone Safari can't, and the
  // test WebKit doesn't; kiosk mode carries on without it.)
  if (browserName === 'chromium') await expect.poll(() => page.evaluate(() => document.fullscreenElement !== null)).toBe(true)

  // Overview, Home, Claude, Money, Services, Schedule, then round again.
  for (const [hash, title] of [['#home', 'Home'], ['#claude', 'Claude'], ['#money', 'Money'], ['#services', 'Services'], ['#schedule', 'Schedule']]) {
    await page.clock.runFor(21_000)
    await expect.poll(() => page.evaluate(() => window.location.hash)).toBe(hash)
    await expect(page.getByRole('heading', { level: 1, name: title, exact: true })).toBeVisible()
    if (hash === '#money') {
      // Purchases with amounts, and nothing big: no net worth, balances or pay.
      await expect(page.getByRole('heading', { name: 'Recent purchases' })).toBeVisible()
      for (const gone of ['Net worth', 'Accounts', 'This month']) await expect(page.getByRole('heading', { name: gone, exact: true })).toHaveCount(0)
      await expect(page.getByRole('button', { name: 'Show amounts' })).toHaveCount(0)
      await expect(page.getByText('Payroll')).toHaveCount(0)
    }
    if (hash === '#services') await expect(page.getByRole('heading', { name: 'Terminal' })).toHaveCount(0)
    // Nothing spills sideways in kiosk mode either.
    expect(await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)).toBeLessThanOrEqual(0)
  }
  await page.clock.runFor(21_000)
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe('#overview')

  // It's remembered across a reload (a deploy), still cycling.
  await page.reload()
  await expect(page.getByRole('button', { name: 'Close kiosk mode' })).toBeVisible()

  await page.getByRole('button', { name: 'Close kiosk mode' }).click()
  await expect(page.getByRole('button', { name: 'Kiosk mode' })).toBeVisible()
  await page.clock.runFor(30_000)
  expect(await page.evaluate(() => window.location.hash)).toBe('#overview')
})

test('kiosk mode waits while I use the page', async ({ page }) => {
  await page.clock.install()
  await page.goto('/')
  await page.getByRole('button', { name: 'Kiosk mode' }).click()
  await page.clock.runFor(10_000)
  // A tap holds the cycle for a minute.
  await page.getByRole('heading', { level: 1 }).click()
  await page.clock.runFor(30_000)
  expect(await page.evaluate(() => window.location.hash)).toBe('')
  await page.clock.runFor(31_000)
  await expect.poll(() => page.evaluate(() => window.location.hash)).toBe('#home')
})

test('while Jarvis looks something up, the orb switches to its working sweep and says what he is doing', async ({ page }) => {
  await page.goto('/talk')
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  // The demo's first question is about the schedule, which needs a calendar lookup.
  // The label shows on /talk (unlike the other states, which stay quiet there), with the orb working.
  await expect(chat.locator('.chat__status:not([data-quiet])', { hasText: 'Checking your calendar.' })).toBeVisible({ timeout: 15_000 })
  await expect(chat.locator('.chat__head .orb[data-state="working"]')).toHaveCount(1)
  // Then the answer follows.
  // .last(): the sample server keeps the chat across tests, so earlier answers may be there too.
  await expect(chat.getByText(/volleyball at 7:30/).last()).toBeVisible({ timeout: 15_000 })
  await expect(chat.locator('.chat__head .orb')).not.toHaveAttribute('data-state', 'working')
})

test('Jarvis shows typing dots until his reply starts', async ({ page }) => {
  // Held until the test lets it go, so the dots can be seen while he "thinks".
  let release: () => void = () => {}
  const held = new Promise<void>((resolve) => { release = resolve })
  await page.route('**/api/jarvis/chat', async (route) => {
    await held
    await route.fulfill({ contentType: 'application/x-ndjson', body: '{"type":"delta","text":"It is 64° and clear."}\n{"type":"done","ok":true}\n' })
  })
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('What is the weather?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  const typing = chat.getByLabel('Jarvis is typing')
  await expect(typing).toBeVisible()
  await expect(typing.locator('.chat__dot')).toHaveCount(3)
  release()
  await expect(chat.getByText('It is 64° and clear.')).toBeVisible()
  await expect(chat.locator('.chat__typing')).toHaveCount(0)
})

test('a chip over each reply says who answered: Jarvis (C) in orange, Jarvis (O) in blue', async ({ page }) => {
  await page.route('**/api/jarvis/chat', (route) => route.fulfill({ contentType: 'application/x-ndjson', body: '{"type":"model","model":"ornith"}\n{"type":"delta","text":"Claude is out of room, so it is me."}\n{"type":"done","ok":true}\n' }))
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('Who is this?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  await expect(chat.getByText('Claude is out of room, so it is me.')).toBeVisible()
  // Earlier sample turns (shared mock server) have their own chips; the newest is the one that matters.
  const chip = chat.locator('.chat__model').last()
  await expect(chip).toHaveText('Jarvis (O)')
  await expect(chip).toHaveAttribute('data-model', 'local')
  // The sample Jarvis (no route) answers as Claude.
  await page.unroute('**/api/jarvis/chat')
  await expect(chat.getByRole('status')).toHaveText('Type below, or tap Talk', { timeout: 10_000 })
  await chat.getByRole('textbox', { name: 'Message Jarvis' }).fill('And now?')
  await chat.getByRole('button', { name: 'Send', exact: true }).click()
  await expect(chat.locator('.chat__model').last()).toHaveText('Jarvis (C)')
  await expect(chat.locator('.chat__model').last()).toHaveAttribute('data-model', 'claude')
})

test('a reply with Markdown shows headings, a table, a list and a divider', async ({ page }) => {
  const reply = '## Headsets\n| Item | Price |\n|---|---|\n| A30 | $900 |\n| A20 | $650 |\n\n---\n- **GA plugs** only\n- posted this week'
  await page.route('**/api/jarvis/chat', (route) => route.fulfill({ contentType: 'application/x-ndjson', body: JSON.stringify({ type: 'delta', text: reply }) + '\n{"type":"done","ok":true}\n' }))
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('Any headset deals?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  const answer = chat.locator('.chat__a').last()
  await expect(answer.getByRole('heading', { name: 'Headsets' })).toBeVisible()
  await expect(answer.getByRole('table')).toBeVisible()
  await expect(answer.getByRole('cell', { name: '$650' })).toBeVisible()
  await expect(answer.getByRole('listitem')).toHaveCount(2)
  await expect(answer.locator('strong')).toHaveText('GA plugs')
  await expect(answer.locator('hr')).toHaveCount(1)
  // No raw Markdown characters are left on screen.
  await expect(answer).not.toContainText('|')
  await expect(answer).not.toContainText('**')
})

test('a wide table in a reply scrolls inside the bubble instead of spilling out', async ({ page }) => {
  const reply = '| Headset | Price | Noise reduction | Plug | Seller | Posted |\n|---|---|---|---|---|---|\n| Bose A30 | $900 | Active | GA dual | Torrance pilot shop | This week |\n| Lightspeed Zulu 3 | $650 | Active | GA dual | Marketplace | Yesterday |'
  await page.route('**/api/jarvis/chat', (route) => route.fulfill({ contentType: 'application/x-ndjson', body: JSON.stringify({ type: 'delta', text: reply }) + '\n{"type":"done","ok":true}\n' }))
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('Compare headsets')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  const answer = chat.locator('.chat__a').last()
  await expect(answer.getByRole('table')).toBeVisible()
  // The scroll box stays inside the bubble, and the bubble inside the chat, at every width.
  const bubble = (await answer.boundingBox())!
  const scroller = (await answer.locator('.md__scroll').boundingBox())!
  const sheet = (await chat.boundingBox())!
  expect(scroller.x + scroller.width).toBeLessThanOrEqual(bubble.x + bubble.width + 1)
  expect(bubble.x + bubble.width).toBeLessThanOrEqual(sheet.x + sheet.width + 1)
})

test('the "…" after a reply says "That was wrong" and opens a pop-up for what he should have said', async ({ page }) => {
  let sent: unknown = null
  await page.route('**/api/jarvis/chat', (route) => route.fulfill({ contentType: 'application/x-ndjson', body: '{"type":"delta","text":"I can only time drives from your phone."}\n{"type":"done","ok":true}\n' }))
  await page.route('**/api/jarvis/feedback', async (route) => { sent = route.request().postDataJSON(); await route.fulfill({ json: { ok: true, message: 'Thanks. Jarvis will work on it tonight.' } }) })
  await page.goto('/')
  await page.getByRole('textbox', { name: 'Question for Jarvis' }).fill('How long to KTOA from home?')
  await page.getByRole('button', { name: 'Ask', exact: true }).click()
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  await expect(chat.getByText('I can only time drives from your phone.')).toBeVisible()
  // A small icon on the reply's last line, not a link under it; nothing else says "That was wrong".
  const wrong = chat.getByRole('button', { name: 'That was wrong' }).last()
  await expect(chat.getByText('That was wrong', { exact: true })).toHaveCount(0)
  const answer = (await chat.getByText('I can only time drives from your phone.').boundingBox())!
  const icon = (await wrong.boundingBox())!
  expect(icon.height).toBeLessThan(30)
  expect(icon.y).toBeGreaterThanOrEqual(answer.y)
  expect(icon.y + icon.height).toBeLessThanOrEqual(answer.y + answer.height + 2)
  // Its tap area still reaches 44 px: 20 px above and below its middle land on it.
  const hits = await wrong.evaluate((el) => {
    const r = el.getBoundingClientRect()
    const x = r.left + r.width / 2
    const y = r.top + r.height / 2
    return [y - 20, y + 20, x - 20].map((v, i) => {
      const hit = i < 2 ? document.elementFromPoint(x, v) : document.elementFromPoint(v, y)
      return hit !== null && el.contains(hit)
    })
  })
  expect(hits).toEqual([true, true, true])
  // A pop-up over the chat, not a form inside it: the chat doesn't move.
  const turnsBefore = (await chat.locator('.chat__turns').boundingBox())!
  const scrollBefore = await chat.locator('.chat__turns').evaluate((el) => el.scrollHeight)
  await wrong.click()
  const popup = page.getByRole('dialog', { name: 'That was wrong' })
  await expect(popup).toBeVisible()
  await expect(chat.locator('.chat__turns').getByRole('form')).toHaveCount(0)
  expect(await chat.locator('.chat__turns').evaluate((el) => el.scrollHeight)).toBe(scrollBefore)
  expect((await chat.locator('.chat__turns').boundingBox())!).toEqual(turnsBefore)
  // Fixed size: the same before and after sending.
  const size = (await popup.boundingBox())!
  const note = popup.getByLabel('What should he have said? (optional)')
  // 16 px, so iPhone Safari doesn't zoom in on it.
  expect(await note.evaluate((el) => getComputedStyle(el).fontSize)).toBe('16px')
  await note.fill('Drive time works from home too.')
  await popup.getByRole('button', { name: 'Send', exact: true }).click()
  await expect(popup.getByText('Thanks. Jarvis will work on that tonight.')).toBeVisible()
  const after = (await popup.boundingBox())!
  expect([after.width, after.height]).toEqual([size.width, size.height])
  expect(sent).toEqual({ question: 'How long to KTOA from home?', answer: 'I can only time drives from your phone.', note: 'Drive time works from home too.' })
  // Close leaves the chat open, and the "…" has left that reply.
  await popup.getByRole('button', { name: 'Close', exact: true }).click()
  await expect(popup).toHaveCount(0)
  await expect(chat).toBeVisible()
  await expect(chat.locator('.chat__turn').last().getByRole('button', { name: 'That was wrong' })).toHaveCount(0)
})

test('/talk shows the same "…" after each of his replies, and Esc closes only its pop-up', async ({ page }) => {
  await page.goto('/talk')
  const chat = page.getByRole('dialog', { name: 'Jarvis' })
  // Sample data plays a demo turn by itself.
  const wrong = chat.getByRole('button', { name: 'That was wrong' }).first()
  await expect(wrong).toBeVisible({ timeout: 20_000 })
  await wrong.click()
  const popup = page.getByRole('dialog', { name: 'That was wrong' })
  await expect(popup.getByRole('form', { name: 'Tell Jarvis what was wrong' })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(popup).toHaveCount(0)
  await expect(chat).toBeVisible()
  await wrong.click()
  await popup.getByRole('button', { name: 'Close', exact: true }).click()
  await expect(popup).toHaveCount(0)
})

test('a faint line at the bottom says which build this is and links its commit', async ({ page }) => {
  await page.goto('/')
  const footer = page.locator('footer.build')
  await expect(footer).toContainText(/^build \S+ · deployed [A-Z][a-z]{2} \d{1,2}, \d{1,2}:\d{2} [AP]M$/)
  // Small and quiet: one line of 11 px type.
  const look = await footer.evaluate((el) => ({ size: getComputedStyle(el).fontSize, height: el.getBoundingClientRect().height }))
  expect(look.size).toBe('11px')
  expect(look.height).toBeLessThan(24)
  // The test build runs in a git checkout, so the commit is real and links to GitHub.
  await expect(footer.getByRole('link')).toHaveAttribute('href', /^https:\/\/github\.com\/dwongbound\/home-lab\/commit\/[0-9a-f]{7,40}$/)
})
