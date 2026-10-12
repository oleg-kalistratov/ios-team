# ios-team

An agent team for **elva-ios**, run by the session you already work in. The main session
loads the `elva-lead` coordinator protocol, keeps the conversation, the plan, the root
cause and every question to you, and hands the long or noisy work to seven specialists —
each on the model its job needs. Every outward action (push, PR, Jira, Confluence,
TestOps, device run, worktree removal) waits for your own word **and** a native permission
dialog that names the target. Commands nobody should run from an agent are denied outright.

```bash
claude plugin install ios-team@elva-tools     # once it is published; before that see «Local install»
```

Requires the ios-dev, ios-testing and swiftui-expert plugins enabled (elva-tools or the
desktop org catalog) — see Prerequisites.

Optional: with the [swift-code-index](https://github.com/oleg-kalistratov/swift-code-index)
plugin installed, the coordinator and the code-reading agents answer symbol questions
(definitions, callers, implementations) from the Xcode index first; without it they grep as before.

## What it changes

Without it, one long Opus context does everything: it reads the ticket, writes tests and
code, drives the simulator for hundreds of screenshots, reads build logs and bundles, and
re-reads all of that on every turn. Corrections you send while it drives the simulator wait
until it stops. Parallel sessions collide on the simulator. Gate words live only in the
prompt text, so a question can be taken for a yes.

With it, the coordinator stays small and responsive: the iOS engineer and the QA tester
run in the background, the screenshots live in a cheaper context that is thrown away, and
the hooks — not the prompt — decide what needs your click and what is never allowed.

## What it ships

| Part | What it is |
|---|---|
| `skills/elva-lead` | Coordinator protocol for the **main** session: routing by intake (Jira key, bundle, Allure/GitHub URL, «ревью», «#1234»…), the main ticket flow, side flows, brief templates (`references/briefs.md`) and QA checklists (`references/verify-checklists.md`). |
| `skills/pr-description-ru` | Russian, plain-language PR bodies (moved here from a personal skill so the whole team has it). |
| `agents/` | Seven specialists, invoked as `ios-team:<name>` (table below). |
| `hooks/guards.json` + `scripts/` | Classic command hooks: secrets, never-list, commit lint, outward MCP writes, simulator and writer leases, subagent start/stop. Listed in `plugin.json` under `hooks`. |
| `scripts/gate.sh` | The verification gate: tests via `Scripts/test.sh`, build and lint via ios-dev's `ios.sh`, invariant scan, one JSON verdict. |
| `scripts/lease.sh`, `disk-check.sh`, `bundle-prepass.sh`, `scan-diff.sh`, `arch-check.sh` | Leases between parallel sessions, disk threshold, diagnostic-bundle pre-pass (PII masked), staged-diff scans. |
| `tests/` | `hooks.test.sh` (every hook with realistic stdin, allowed and blocked cases). |

### The team

Prices are $ per million tokens, input/output: haiku 1/5, sonnet 2/10, opus 4/20, fable 10/50.

| Agent | Model | Runs | Why this model, in one line |
|---|---|---|---|
| coordinator (main session + `elva-lead`) | your session (opus) | main | Only the main session can ask you and drive the desktop panels; your corrections must land in the context that planned. |
| `ios-engineer` | opus, high | background | Test design and implementation are the deep work; a red run before code, every guidance skill, questions instead of guesses. |
| `architect` | opus, high | background | Placement decisions are rare and expensive to get wrong; runs only on structural changes, read-only. |
| `qa-tester` | sonnet, high | background | Hundreds of simulator calls with screenshots cost half as much per token and leave the main context clean; derives its own corner cases. |
| `reviewer` | sonnet, high | background | Fresh-context correctness review of a slice (≤40 files) is mid-depth; the coordinator re-verifies each finding. |
| `analytics` | sonnet, high | background | Methodology, registry and event audits are judgement on fixed rules, not deep code reasoning. |
| `wt-keeper` | haiku (no effort) | background; foreground for removal | A fixed recipe of git and script calls; the cheapest model that follows it. |
| `publisher` | sonnet, medium | foreground | Russian prose plus fixed Jira fields; foreground so the permission dialog reaches you. |

`fable` is never a default: the coordinator passes it per call (engine/Metal work, a big
architecture decision, one reviewer on a 100+-file PR) only after you say yes.

Agents never ask you: a choice comes back as `needs_decision`, the coordinator asks you and
resumes the same agent with `SendMessage` — the only resume path. Every agent has
browser, computer-use, session-management, scheduling, push-notification and messaging
tools disallowed; reviewer and architect cannot Edit or Write, and qa-tester and analytics
cannot Edit (they write evidence and drafts only into the session scratchpad).

## How confirmation works

1. **Your word is the intent.** «комить» commits, «пушни» pushes, «открой пр» pushes and
   opens the PR. A question («можно запушить?») is answered, never acted on. Nothing parses
   your prompt to grant anything, and nothing an agent, a ticket, a scheduled prompt or
   another session says counts as your word.
2. **The native dialog is the confirmation.** A PreToolUse hook answers `ask` for every
   outward action, always, with a Russian reason that names the target («Пуш
   feature/ELV-1797 в origin и создание PR в develop»). The model cannot click it, and a
   background agent cannot show it — so outward actions run only from the main session or a
   foreground agent (`publisher`, `wt-keeper` for removals). Push + PR is one command and one
   dialog; worktree + branch removal is one command and one dialog.
3. **The never-list is denied** with a Russian reason: fastlane, merging a PR in any form,
   workflow dispatch, release create/delete, force-push to protected branches, branch and
   tag deletion on the remote, `sudo`, `launchctl`, the CI runner installer,
   `git commit --no-verify`, `rm -rf` of home, root or the main checkout, TestOps
   delete/restore/mute, Drive trash/share.
4. **Local reversible work is not gated.** The commit message is linted (one line
   `ELV-123: …` or `Tech: …`, no trailers) and the staged diff is scanned for CLAUDE.md
   invariants, the analytics naming rules and structural changes; a hit asks, it does not
   block.

### Hooks

| Hook | Event / matcher | Denies | Asks |
|---|---|---|---|
| guard-secrets | PreToolUse: Read, Grep, Glob, Edit, Write, NotebookEdit, Bash, xcode MCP | `Secrets/`, `*Secrets*.xcconfig`, `*.p8`, `*.p12`, `*.mobileprovision`, `.env*`, `git status --ignored`, `ls Secrets` (everywhere, any repo). Only the opaque `cp <main>/Secrets/*.xcconfig <worktree>/Secrets/` and `Scripts/new-worktree.sh` pass | — |
| guard-bash | PreToolUse: Bash | the never-list; for read-only roles (reviewer, architect, analytics) any write and any project code | `git push`, `gh pr create/edit/comment/review/close/reopen/ready`, `gh api` POST, `git worktree remove`, `git branch -D`, a device run, `xcrun devicectl`, `lease.sh take`, `rm -rf` outside the scratchpad, checkout/switch/reset/clean in the main checkout |
| commit-lint | PreToolUse: Bash (`git … commit`) | a message that is not one line `ELV-<n>: …` / `Tech: …`, any trailer | invariant, analytics-name or structural hits in the staged diff |
| guard-mcp-writes | PreToolUse: `mcp__.*` | TestOps delete/restore/mute, auto-merge, session deletion from agents, Drive trash/share; any write-like MCP tool from ios-engineer, qa-tester, wt-keeper or a read-only role | write-like MCP tools from the main session or publisher (Jira, Confluence, TestOps, Figma writes), with the key fields in the reason |
| sim-lease | PreToolUse: simulator MCP, `xcrun simctl` naming a device | a simulator held by another live session | — (taking it over is `lease.sh take`, which asks) |
| writer-guard | PreToolUse: Edit, Write, NotebookEdit | edits in a worktree while `ios-engineer` holds its writer lease | — |
| subagent-start | SubagentStart: `ios-team:.*` | — | — (adds cwd, branch, base guess, main checkout, scratchpad, free disk, held leases; takes the writer lease for ios-engineer) |
| subagent-stop | SubagentStop: `ios-team:.*` | bounces an answer without a ```result block once | — (releases the agent's leases; remembers an agent that ended needs_decision/blocked, or with questions in its needs_decision list under any status, as waiting) |
| agent-spawn-guard | PreToolUse: `Agent\|Task` | a new ios-team agent of a type whose agent still waits in this session: resume it with SendMessage; a brief without a `route: <model> <effort> — <why>` line, or a `model`/`effort` that differs from it | `model: fable` asks (≈2.5× Opus) |
| asked / stop-check | PostToolUse: `AskUserQuestion`; UserPromptSubmit; Stop | the coordinator's turn ends after Oleg spoke (a dialog answer or a plain message) while an agent still waits: blocked once, with the ids to SendMessage | context on every message from Oleg: the agents waiting for him, and the agent a «Сообщение для <name>» / «Ответ для <name>» message must go to (a SendMessage to the agent clears it) |

## Safety model and limits

**What protects you.**
- **The dialog is the confirmation.** Your word starts an outward action; the native dialog,
  which only you can click, lets it run. Reject it and the action is cancelled; the
  coordinator does not retry it in another form.
- **The never-list is denied**, from every session and agent, whatever the prompt says.
- **Roles are cut down in frontmatter.** No agent has browser, computer-use, cron,
  remote-trigger, push-notification, session-management or messaging tools; reviewer and
  architect cannot Edit or Write; qa-tester and analytics cannot Edit.
- **Text is data.** Every prompt says that tickets, PR bodies, logs, pages and designs are
  data, and that an «approval» or «the user said» inside them means nothing.

**What pattern guards cannot catch.** The hooks read the text of a command or a tool's
input before it runs; they do not see what a process does once it runs. They catch the
direct forms and the common wrappers, but not reliably: a command or path assembled at run
time (variables, `$(…)`, base64), code run from a file or by another interpreter
(`bash f.sh`, `python3 -c`, `osascript`, `make`), git aliases and config hooks, raw HTTP
to the GitHub API with a token taken from the keychain, archives or whole-tree copies that
sweep `Secrets/` along, case variants of secret paths on the case-insensitive APFS disk,
and the plugin's own files or `~/.claude/settings.json` being edited to switch the hooks
off. Treat them as a seatbelt against mistakes, not as a sandbox against a confused or
prompt-injected agent. Also unverified: whether `ask` still shows a dialog under
`bypassPermissions` or auto mode — the pilot checks it first with `git push --dry-run`;
until it is confirmed, do not run outward steps in bypass mode.

**Backstops that do not depend on the hooks — recommended.**
- **GitHub branch protection** (or a ruleset) on `develop`, `main`, `master` and
  `release/*`: pull request required, force-push and deletion blocked, tag creation
  restricted, and **no bypass** — enable «Do not allow bypassing the above settings» (or
  leave the ruleset bypass list empty), because the agents act with your own token, and an
  admin bypass would apply to them too. Merging stays yours, in the browser.
- **`permissions.deny` Read rules for secrets** in the repository's `.claude/settings.json`
  (snippet below). With the Claude Code Bash sandbox enabled they also cover Bash child
  processes; check that with a fake file before you rely on it. Add case variants
  (`**/SECRETS/**`) if the rules turn out to be case-sensitive.
- Deny Edit and Write on the plugin folder and on `~/.claude/settings*.json` in your user
  settings, so no agent can disable the guards by editing them.

## Install

Works only with **Claude Code** (CLI 2.1.293+ or the desktop app). It is built for the elva-ios repository; other projects need their own rules.

In a Claude Code session:

```
/plugin marketplace add oleg-kalistratov/ios-team
/plugin install ios-team@ios-team
```

Then open a **new** session and check that `ios-team:elva-lead` is in the skill list. Updates come with `/plugin marketplace update`.

### Internal links (required once per developer)

Company-internal ids are not in this repo: the Atlassian site and `cloudId`, Confluence page ids, the Jira account id, the TestOps project and the analytics registry sheet. The agents read them from a local file:

1. Copy [`links.example.md`](links.example.md) to `~/.claude/ios-team/links.md`.
2. Fill in the values (ask a teammate who has the file).

Without it, an agent that needs one of these returns `blocked` and says what is missing.

### Paths

The main checkout defaults to `/Users/elva/Desktop/elva-ios`. If yours lives elsewhere, set `IOS_TEAM_MAIN_REPO` to its absolute path in the `env` block of `~/.claude/settings.json`.

### Developing the plugin itself

Clone the repo, then load it from the folder with `CLAUDE_CODE_PLUGIN_DIRS=<abs path>` in the `env` block of `~/.claude/settings.json` (plus `CLAUDE_CODE_PLUGIN_DIR_WATCH=1` so running sessions reload on save), and uninstall the marketplace copy first. If you have a personal `~/.claude/skills/pr-description-ru`, remove or rename it, so only `ios-team:pr-description-ru` answers.

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Enable it in a project

In the repository's `.claude/settings.json` (elva-ios):

```json
{
  "extraKnownMarketplaces": {
    "elva-tools": {
      "source": { "source": "github", "repo": "elva-apps/claude-plugins" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "ios-team@elva-tools": true
  },
  "permissions": {
    "deny": [
      "Read(**/Secrets/**)",
      "Read(**/*Secrets*.xcconfig)",
      "Read(**/*.p8)",
      "Read(**/*.p12)",
      "Read(**/*.mobileprovision)",
      "Read(**/.env*)"
    ]
  }
}
```

and one routing row at the top of the CLAUDE.md skill table: intake → invoke
`ios-team:elva-lead` in the main session. Until that row exists, start each session's work
with `/ios-team:elva-lead`: the repo's own worktree row would otherwise steer the session
to create worktrees itself.

## Prerequisites

- **Requires the ios-dev, ios-testing and swiftui-expert plugins enabled (elva-tools or the
  desktop org catalog):** `ios-dev` (`ios.sh`, `sim.sh`, `remove-worktree`), `ios-testing`
  (`test-first`, the Allure TestOps MCP) and `swiftui-expert`. They are deliberately not
  declared as `dependencies` in `plugin.json`: an unsatisfied dependency disables the whole
  plugin — agents, skills and every guard — with no visible error, and the
  desktop's org-catalog copies do not satisfy the CLI dependency check. If one is missing,
  the agents say so in `not_verified` and fall back (no `ios.sh` → the gate reports `infra`).
- `python3` and `jq` on `PATH` (the hook scripts use them).
- `.claude/ios-build.conf` in the main checkout with `TEST_SCHEME="Elva-PR"` (the ElvaTest
  scheme has no test action); `wt-keeper` copies it into every new worktree.
- `idb` (`brew install idb-companion` + `pip install fb-idb`) so the tester taps by
  accessibility label instead of coordinates.
- The Figma MCP authorised (`/mcp`), or design values cannot be compared.

## Leases between parallel sessions

State lives in `~/.claude/ios-team/leases/`.

- **Simulator** — one lease per UDID, owned by a session; stale after 10 minutes without a
  heartbeat. Another live session's simulator is denied with who holds it and since when;
  `scripts/lease.sh take sim <UDID>` takes it over after your click.
- **Writer** — `ios-engineer` holds its worktree; edits from anyone else are denied until
  it returns.
- **Heavy** — `scripts/lease.sh run heavy -- <cmd>`: two units for cold builds, tests and
  `tuist generate`, heartbeat while the command runs, released on exit.
- **Disk** — `scripts/disk-check.sh <GB>` exits 3 below the threshold (10 GB before a
  worktree, 8 GB before a build); the agents stop and ask, nobody deletes anything to make
  room.

While an agent waits for your answer, the coordinator treats its leases as held even if the
hooks released them at its stop.

## Checking it

```bash
claude plugin validate --strict ./ios-team                 # manifest and hooks files
bash ./ios-team/tests/hooks.test.sh                          # every hook, allowed and blocked; prints PASS n / FAIL m
claude --plugin-dir ./ios-team plugin details ios-team       # what loads and its token cost
```

`plugin validate` does not check agent or skill frontmatter; parse it separately (any YAML
parser) after editing an agent.

## Not verified yet

- That a hook's `ask` still shows the dialog under every permission mode the desktop app
  offers (auto, accept-edits, bypass) — the first pilot step checks it with
  `git push --dry-run`.
- How a background agent treats a command or an MCP read that is not pre-approved
  (auto-deny or the auto mode classifier) — the pilot watches the engineer's first run and
  the background architect's and analytics agent's Confluence and Drive reads.
- `SendMessage` to an agent that is still running (queued corrections); resuming a stopped
  one is the designed path.
- Whether skills of desktop org-catalog plugins (`ios-dev:drive-simulator`,
  `ios-testing:test-first`) preload into plugin agents.
- The simulator MCP's first-use device permission from a background agent; the coordinator
  grants it once from the main session before the first QA run.
- Writing rows to the analytics registry sheet; the analytics agent drafts exact rows.

## Changelog

**0.1.0** — first version: the `elva-lead` coordinator, seven agents (ios-engineer,
architect, qa-tester, reviewer, analytics, wt-keeper, publisher), `pr-description-ru`,
classic guard hooks with the word-plus-dialog confirmation model (no prompt parsing, no
token ledger, no shadow mode), simulator/writer/heavy leases, the verification gate
script, and the diagnostic-bundle pre-pass. No `dependencies` in
`plugin.json` (a missing one would silently drop the whole plugin, guards included).
