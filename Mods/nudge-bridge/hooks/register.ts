import type { EngineInterface, Register } from 'claude-code'

import type { IosProject, RepoInfo } from '../types'

// Mirrors other mods' state into ~/Library/Application Support/Nudge/feeds/<session>.json,
// which Nudge.app watches to fill its Project tab. It only reads those mods' state.
//
// The other way, Nudge's Touch Bar buttons write commands/<session>.json; this picks a
// command up once and submits the same prompts ios-dock's buttons do.
//
// It also lists every mod's slash commands in mods.json, so Nudge can offer any mod's commands
// as Touch Bar buttons; a button's prompt `/<command>` is run as that command.

const REPO = { plugin: 'ios-dock', key: 'repo' } as const
const PROJECT = { plugin: 'ios-dock', key: 'project' } as const
const BUILD = { plugin: 'ios-dock', key: 'build' } as const
const SHIP = { plugin: 'ios-dock', key: 'ship' } as const
const LINT = { plugin: 'swift-design-lint', key: 'tally' } as const

const INTERVAL_MS = 1_000

/** Kept in step with ios-dock's ACTIONS. */
const PROMPTS: Record<string, (project: IosProject | null, repo: RepoInfo | null) => string[] | null> = {
  build: p => p && [
    `nudge: the user pressed Build on the Touch Bar for ${p.name}.`,
    `Build the Xcode project in ${p.root} through the xcode MCP (XcodeOpenWorkspace, BuildProject, then GetBuildLog with severity "warning").`,
    'If it fails, fix the errors and build again until it is clean. Report the warnings at the end.',
  ],
  lint: p => p && [
    `nudge: the user pressed Design lint & fix on the Touch Bar for ${p.name}.`,
    `In ${p.root}, list the Swift files changed on this branch against the default branch, plus uncommitted ones.`,
    "Check each against the project's CLAUDE.md design-system and architecture rules (typography, icons, colors, buttons, MV vs MVVM and so on).",
    'Fix the violations, touching only the offending lines, then build once to confirm it compiles. Summarize what you changed and anything you left on purpose.',
  ],
  commit: (_, r) => r && [
    `nudge: the user pressed Review & commit on the Touch Bar for ${r.name}.`,
    `In ${r.root}, review the uncommitted changes for bugs and leftovers, then propose an atomic commit grouping with messages.`,
    'Do not commit yet: wait for the user to approve the grouping in their next message.',
  ],
}

let timer: { cancel: () => void } | undefined
let lastWritten = ''
/** null until the first sample, whose build (if any) predates this load and has no known age. */
let lastBuild: string | null = null
/** When ios-dock's build result last changed, so Nudge can tell it from a newer Xcode build. */
let buildAt: number | null = null
let lastCommand = ''
let lastCatalog = ''
const CATALOG_EVERY = 30

/** The slash commands plugins add, by plugin, for Nudge to offer as buttons. */
async function publishCatalog($: EngineInterface) {
  const where = await folder($)
  if (!where) return
  const catalog: Record<string, { name: string; description: string }[]> = {}
  for (const command of await $.command.list()) {
    if (command.source !== 'plugin' || !command.plugin || command.plugin === 'nudge-bridge') continue
    ;(catalog[command.plugin] ??= []).push({ name: command.name, description: command.description })
  }
  const body = JSON.stringify(catalog)
  if (body === lastCatalog) return
  lastCatalog = body
  await $.fs.write(`${where.base}/mods.json`, body)
}

/** `/name args` when it names a command this session has; Nudge's mod buttons send these. */
async function slashCommand($: EngineInterface, text: string) {
  const match = /^\/(\S+)\s*([\s\S]*)$/.exec(text.trim())
  if (!match) return null
  const known = (await $.command.list()).some(listed => listed.name === match[1])
  const [, command = '', args = ''] = match
  return known ? { command, args } : null
}

async function folder($: EngineInterface): Promise<{ base: string; session: string } | null> {
  const [home, session] = await Promise.all([$.env.get('HOME'), $.session.id()])
  return home ? { base: `${home}/Library/Application Support/Nudge`, session } : null
}

async function publish($: EngineInterface) {
  const [repo, project, build, ship, lint] = await Promise.all([
    $.state.get(REPO), $.state.get(PROJECT), $.state.get(BUILD), $.state.get(SHIP), $.state.get(LINT),
  ])
  const feed = {
    repo: repo.value ?? null,
    project: project.value ?? null,
    build: build.value ?? null,
    ship: ship.value ?? null,
    lint: lint.value ?? null,
    // What this plugin offers; Nudge shows whatever is listed here.
    actions: [
      ...(project.value ? [{ id: 'build', title: 'Build', symbol: 'hammer' }, { id: 'lint', title: 'Lint', symbol: 'wand.and.stars' }] : []),
      ...(repo.value ? [{ id: 'commit', title: 'Commit', symbol: 'checkmark.circle' }] : []),
    ],
    badges: lint.value && lint.value.checkedEdits > 0 && lint.value.issues > 0
      ? [{ symbol: 'pencil.line', title: String(lint.value.issues), detail: lint.value.issues === 1 ? 'lint issue' : 'lint issues', tint: 'orange' }]
      : [],
  }
  const body = JSON.stringify(feed)
  if (body === lastWritten) return

  const [where, cwd, now] = await Promise.all([folder($), $.session.cwd(), $.clock.now()])
  if (!where) return
  lastWritten = body
  const buildJSON = JSON.stringify(feed.build)
  if (lastBuild === null) {
    lastBuild = buildJSON
  } else if (buildJSON !== lastBuild) {
    lastBuild = buildJSON
    buildAt = feed.build ? Math.floor(now / 1000) : null
  }
  await $.fs.write(
    `${where.base}/feeds/${where.session}.json`,
    JSON.stringify({ session: where.session, cwd, updatedAt: Math.floor(now / 1000), buildAt, ...feed }),
  )
}

async function takeCommand($: EngineInterface) {
  const where = await folder($)
  if (!where) return
  const path = `${where.base}/commands/${where.session}.json`
  const text = await $.fs.read(path).catch(() => '')
  if (!text.trim()) return

  let command: { id?: string; action?: string; prompt?: string }
  try {
    command = JSON.parse(text)
  } catch {
    return
  }
  if (!command.id || command.id === lastCommand) return
  lastCommand = command.id
  await $.fs.write(path, '')

  const [repo, project] = await Promise.all([$.state.get(REPO), $.state.get(PROJECT)])
  // A button made in Nudge's Settings arrives already worded; a mod's command runs as typed.
  const slash = command.prompt ? await slashCommand($, command.prompt) : null
  if (slash) {
    $.clock.after(1, () => void $.command.run(slash).catch(() => {}))
    return
  }
  const lines = command.prompt ? [command.prompt] : PROMPTS[command.action ?? '']?.(project.value ?? null, repo.value ?? null)
  if (lines) $.clock.after(1, () => void $.prompt.submit({ text: lines.join('\n\n') }))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    timer?.cancel()
    let tick = 0
    $.clock.after(1, () => void publishCatalog($).catch(() => {}))
    timer = $.clock.every(INTERVAL_MS, () => {
      void publish($).catch(() => {})
      void takeCommand($).catch(() => {})
      if (++tick % CATALOG_EVERY === 0) void publishCatalog($).catch(() => {})
    })
    return next(e)
  })
}
