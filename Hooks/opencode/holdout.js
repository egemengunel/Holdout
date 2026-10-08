// Holdout's OpenCode plugin. OpenCode has no command hooks, so this forwards session
// activity to ../holdout-hook.sh as Claude Code-shaped hook payloads. `Hooks/install.sh`
// loads it from ~/.config/opencode/plugins/. Failures are swallowed: it must never
// get in OpenCode's way.
//
// The other way, a Touch Bar button writes commands/<session>.json; this submits its
// prompt to that session, as the holdout-bridge mod does for Claude Code.
import { spawn } from "node:child_process"
import { readFileSync, unlinkSync } from "node:fs"
import { homedir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const hook = join(dirname(fileURLToPath(import.meta.url)), "..", "holdout-hook.sh")
const commands = join(homedir(), "Library/Application Support/Holdout/commands")

function takeCommand(sessionID) {
  const path = join(commands, `${sessionID}.json`)
  try {
    const command = JSON.parse(readFileSync(path, "utf8"))
    unlinkSync(path)
    return typeof command.prompt === "string" && command.prompt ? command.prompt : null
  } catch {
    return null
  }
}

function send(payload) {
  try {
    const child = spawn("/bin/sh", [hook, "opencode"], { stdio: ["pipe", "ignore", "ignore"] })
    child.on("error", () => {})
    child.stdin.on("error", () => {})
    child.stdin.end(JSON.stringify(payload))
  } catch {}
}

const core = ({ client, directory }) => {
  // Sessions mid-turn, so a turn's start and end are reported once each.
  const busy = new Set()
  // Subagent sessions run inside a parent's turn; the parent already shows it.
  const children = new Set()
  const sessions = new Set()

  const report = (sessionID, event, extra = {}) => {
    if (!sessionID || children.has(sessionID)) return
    sessions.add(sessionID)
    send({ session_id: sessionID, hook_event_name: event, cwd: directory, ...extra })
  }

  setInterval(() => {
    for (const id of sessions) {
      const text = takeCommand(id)
      if (!text) continue
      try {
        const submit = client?.session?.promptAsync ?? client?.session?.prompt
        submit?.call(client.session, { path: { id }, body: { parts: [{ type: "text", text }] } })?.catch?.(() => {})
      } catch {}
    }
  }, 2000).unref?.()
  const begin = (sessionID) => {
    if (sessionID && !busy.has(sessionID)) {
      busy.add(sessionID)
      report(sessionID, "UserPromptSubmit")
    }
  }
  const finish = (sessionID) => {
    if (busy.delete(sessionID)) report(sessionID, "Stop")
  }

  const hooks = {
    event: async ({ event }) => {
      const properties = event.properties ?? {}
      switch (event.type) {
        case "session.created":
          if (properties.info?.parentID) children.add(properties.info.id)
          else report(properties.info?.id, "SessionStart", { cwd: properties.info?.directory ?? directory })
          break
        case "session.deleted":
          busy.delete(properties.info?.id)
          report(properties.info?.id, "SessionEnd")
          children.delete(properties.info?.id)
          sessions.delete(properties.info?.id)
          break
        case "session.status":
          if (properties.status?.type === "busy") begin(properties.sessionID)
          else if (properties.status?.type === "idle") finish(properties.sessionID)
          break
        case "session.idle":
          finish(properties.sessionID)
          break
        case "permission.asked":
        case "permission.updated":
          report(properties.sessionID, "Notification", { notification_type: "permission_prompt", message: properties.title })
          break
        case "permission.replied":
          report(properties.sessionID, "PostToolUse")
          break
      }
    },
    "tool.execute.before": async (input, output) => {
      begin(input.sessionID)
      report(input.sessionID, "PreToolUse", { tool_name: input.tool, tool_input: output?.args })
    },
    "tool.execute.after": async (input) => {
      report(input.sessionID, "PostToolUse", { tool_name: input.tool, tool_input: input.args })
    },
  }
  return { hooks, report, begin, finish, sessions, busy, children }
}

// OpenCode 1.18.29+ (`server`) and 2.0 (`setup`) take different plugin shapes, so one default
// export carries both. 2.0 has no hook map: its events (session.execution.started, ...) come
// through `ctx.event.subscribe` and are translated to the same reports.
export default {
  id: "holdout",
  async server(input) {
    return core(input).hooks
  },
  setup(ctx) {
    const { report, begin, finish, sessions, busy, children } = core({ client: ctx.client, directory: ctx.location?.directory })
    const controller = new AbortController()
    const toolNames = new Map()

    const translate = (event) => {
      const data = event.data ?? {}
      const id = data.sessionID ?? event.durable?.aggregateID
      const directory = event.location?.directory
      switch (event.type) {
        case "session.created":
          if (data.parentID) children.add(id)
          else report(id, "SessionStart", { cwd: directory })
          break
        case "session.deleted":
          busy.delete(id)
          report(id, "SessionEnd")
          children.delete(id)
          sessions.delete(id)
          break
        case "session.execution.started":
          begin(id)
          break
        case "session.execution.succeeded":
        case "session.execution.failed":
        case "session.execution.cancelled":
        case "session.execution.interrupted":
          finish(id)
          break
        case "session.tool.input.started":
          toolNames.set(data.id, data.name)
          report(id, "PreToolUse", { tool_name: data.name })
          break
        case "session.tool.success":
        case "session.tool.failed":
        case "session.tool.error":
          report(id, "PostToolUse", { tool_name: toolNames.get(data.id) })
          toolNames.delete(data.id)
          break
        default:
          // Approval prompts: their event names aren't documented, so match by meaning.
          if (/permission|approval/.test(event.type)) {
            if (/(asked|requested|pending)/.test(event.type)) {
              report(id, "Notification", { notification_type: "permission_prompt" })
            } else if (/(replied|granted|denied|answered|resolved)/.test(event.type)) {
              report(id, "PostToolUse")
            }
          }
      }
    }

    void (async () => {
      try {
        for await (const event of ctx.event.subscribe({ signal: controller.signal })) {
          try { translate(event) } catch {}
        }
      } catch {}
    })()
    return () => controller.abort()
  },
}
