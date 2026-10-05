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

export const Holdout = async ({ client, directory }) => {
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

  return {
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
}
