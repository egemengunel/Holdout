// The slices of ios-dock's and swift-design-lint's state contracts this bridge reads.
// Kept in step with ~/.claude/mods/*/types/index.d.ts; the bridge never writes them.

export type IosProject = {
  name: string
  root: string
  architecture: 'MV' | 'MVVM'
  deploymentTarget: string | null
  isSynced: boolean
  branch: string | null
  hasTestflight: boolean
}

export type RepoInfo = { name: string; root: string; branch: string | null }

export type IosBuild = {
  project: string
  isOk: boolean
  seconds: number
  errorCount: number
  firstError: string | null
  warningCount: number | null
}

export type IosShip = {
  phase: 'idle' | 'confirm' | 'running' | 'shipped' | 'conflict' | 'failed'
  ahead: number
  unpushedMain: number
  note: string | null
}

export type LintTally = { issues: number; lastFile: string | null; checkedEdits: number }

declare module 'claude-code' {
  interface PluginState {
    'ios-dock': { repo: RepoInfo | null; project: IosProject | null; build: IosBuild | null; ship: IosShip }
    'swift-design-lint': { tally: LintTally }
  }
}
