# ios-team

An agent team for an **iOS repository** (Tuist, Swift, SwiftUI), run by the session you already work in. The main session
loads the `lead` coordinator protocol, keeps the conversation, the plan, the root
cause and every question to you, and hands the long or noisy work to seven specialists —
each on the model its job needs. Every outward action (push, PR, Jira, Confluence,
TestOps, device run, worktree removal) waits for your own word **and** a native permission
dialog that names the target. Commands nobody should run from an agent are denied outright.

```
/plugin marketplace add oleg-kalistratov/ios-team
/plugin install ios-team@ios-team
```

Then create `~/.claude/ios-team/project.md` from [`project.example.md`](project.example.md) — see «Project settings».

Requires the ios-dev, ios-testing and swiftui-expert plugins enabled (your plugin marketplace or
the desktop org catalog) — see Prerequisites.

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
| `skills/lead` (`/ios-team:lead`) | Coordinator protocol for the **main** session: routing by intake (Jira key, bundle, Allure/GitHub URL, «ревью», «#1234»…), the main ticket flow, side flows, brief templates (`references/briefs.md`) and QA checklists (`references/verify-checklists.md`). |
| `skills/pr-description-ru` | Russian, plain-language PR bodies (moved here from a personal skill so the whole team has it). |
| `agents/` | Seven specialists, invoked as `ios-team:<name>` (table below). |
| `hooks/guards.json` + `scripts/` | Classic command hooks: secrets, never-list, commit lint, outward MCP writes, simulator and writer leases, subagent start/stop. Listed in `plugin.json` under `hooks`. |
| `scripts/gate.sh` | The verification gate: tests via `Scripts/test.sh`, build and lint via ios-dev's `ios.sh`, invariant scan, one JSON verdict. |
| `scripts/lease.sh`, `disk-check.sh`, `bundle-prepass.sh`, `scan-diff.sh`, `arch-check.sh` | Leases between parallel sessions, disk threshold, diagnostic-bundle pre-pass (PII masked), staged-diff scans. |
| `project.example.md`, `links.example.md` | Templates for the two local files the team reads: project values and company-internal ids. |
| `scripts/check-neutral.sh` | Fails on any project or company name in the repo; the suite runs it. |
| `tests/` | `hooks.test.sh` (every hook with realistic stdin, allowed and blocked cases, against a neutral sandbox `project.md`). |

### The team

Prices are $ per million tokens, input/output: haiku 1/5, sonnet 2/10, opus 4/20, fable 10/50.

| Agent | Model | Runs | Why this model, in one line |
|---|---|---|---|
| coordinator (main session + `lead`) | your session (opus) | main | Only the main session can ask you and drive the desktop panels; your corrections must land in the context that planned. |
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
   feature/ABC-123 в origin и создание PR в develop»). The model cannot click it, and a
   background agent cannot show it — so outward actions run only from the main session or a
   foreground agent (`publisher`, `wt-keeper` for removals). Push + PR is one command and one
   dialog; worktree + branch removal is one command and one dialog.
3. **The never-list is denied** with a Russian reason: fastlane, merging a PR in any form,
   workflow dispatch, release create/delete, force-push to protected branches, branch and
   tag deletion on the remote, `sudo`, `launchctl`, the CI runner installer,
   `git commit --no-verify`, `rm -rf` of home, root or the main checkout, TestOps
   delete/restore/mute, Drive trash/share.
4. **Local reversible work is not gated.** The commit message is linted (one line
   matching `commit_pattern` from `project.md`, e.g. `ABC-123: …` or `Tech: …`, no trailers) and the staged diff is scanned for CLAUDE.md
   invariants, the analytics naming rules and structural changes; a hit asks, it does not
   block.

### Hooks

| Hook | Event / matcher | Denies | Asks |
|---|---|---|---|
| guard-secrets | PreToolUse: Read, Grep, Glob, Edit, Write, NotebookEdit, Bash, xcode MCP | `Secrets/`, `*Secrets*.xcconfig`, `*.p8`, `*.p12`, `*.mobileprovision`, `.env*`, `git status --ignored`, `ls Secrets` (everywhere, any repo). Only the opaque `cp <main>/Secrets/*.xcconfig <worktree>/Secrets/` and `Scripts/new-worktree.sh` pass | — |
| guard-bash | PreToolUse: Bash | the never-list; for read-only roles (reviewer, architect, analytics) any write and any project code | `git push`, `gh pr create/edit/comment/review/close/reopen/ready`, `gh api` POST, `git worktree remove`, `git branch -D`, a device run, `xcrun devicectl`, `lease.sh take`, `rm -rf` outside the scratchpad, checkout/switch/reset/clean in the main checkout |
| commit-lint | PreToolUse: Bash (`git … commit`) | a message that is not one line matching `commit_pattern` from `project.md` (default `<KEY>-<n>: …` / `Tech: …`), any trailer | invariant, analytics-name or structural hits in the staged diff |
| guard-mcp-writes | PreToolUse: `mcp__.*` | TestOps delete/restore/mute, auto-merge, session deletion from agents, Drive trash/share; any write-like MCP tool from ios-engineer, qa-tester, wt-keeper or a read-only role | write-like MCP tools from the main session or publisher (Jira, Confluence, TestOps, Figma writes), with the key fields in the reason |
| sim-lease | PreToolUse: simulator MCP, `xcrun simctl` naming a device | a simulator held by another live session | — (taking it over is `lease.sh take`, which asks) |
| writer-guard | PreToolUse: Edit, Write, NotebookEdit | edits in a worktree while `ios-engineer` holds its writer lease | — |
| subagent-start | SubagentStart: `ios-team:.*` | — | — (adds cwd, branch, base guess, main checkout, scratchpad, free disk, held leases; takes the writer lease for ios-engineer) |
| subagent-stop | SubagentStop: `ios-team:.*` | bounces an answer without a ```result block once | — (releases the agent's leases; remembers an agent that ended needs_decision/blocked, or with questions in its needs_decision list under any status, as waiting) |
| agent-spawn-guard | PreToolUse: `Agent\|Task` | a new ios-team agent of a type whose agent still waits in this session: resume it with SendMessage; a brief without a `route: <model> <effort> — <why>` line (the model router, `lead` §6), or a `model`/`effort` that differs from it | `model: fable` asks (≈2.5× Opus) |
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
prompt-injected agent.

**Bypass mode.** When you switch the session to `bypassPermissions` yourself, the hooks read
`permission_mode` from their input and answer `allow` wherever they would have asked: push,
PR create/edit, Jira/Confluence/TestOps writes, worktree and branch removal, lease take,
device runs, `rm -rf` outside scratch, and also edits to the plugin or Claude Code settings,
commands the guard could not parse or verify (a `$VAR` command name, piped code), commit-lint
and arch-check findings and Fable spawns. Each such allow is appended as one JSON line
(time, session, agent, tool, cwd, the reason the dialog would have shown) to
`~/.claude/ios-team/state/bypass-allowed.jsonl` — read it after an unattended run. Denies stay
denies in every mode: the release tool, PR merge, secrets, force and delete pushes, `--no-verify`,
switching the hooks off, sudo and the rest of the never-list, plus subagent bans.

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

Works only with **Claude Code** (CLI 2.1.293+ or the desktop app). It is built for a Tuist-based iOS repository whose CLAUDE.md holds the project rules; your project's own values go into `~/.claude/ios-team/project.md` (below).

In a Claude Code session:

```
/plugin marketplace add oleg-kalistratov/ios-team
/plugin install ios-team@ios-team
```

Then open a **new** session and check that `ios-team:lead` is in the skill list (`/ios-team:lead` starts it by hand). Updates come with `/plugin marketplace update`.

### Project settings (required once per developer)

Nothing project-specific is in this repo: the repository and workspace names, schemes, test plans, bundle ids, the URL
scheme, the dedicated simulator prefix, the commit pattern and the engine module names live in a local file that the
agents and the hook scripts read:

1. Copy [`project.example.md`](project.example.md) to `~/.claude/ios-team/project.md`.
2. Fill in your project's values; each key has a one-line comment that says what it is for.

Without it, an agent that needs one of these values returns `blocked`: «нет ~/.claude/ios-team/project.md — создай его по
project.example.md». `gate.sh` reports `infra`. The hooks never break on a missing file: the guards keep their policy
(secrets and the never-list are still denied, outward actions still ask), commit-lint falls back to the generic pattern
`^[A-Z][A-Z0-9]+-[0-9]+: .+|^Tech: .+` and applies to Tuist-layout repos (Project.swift + Modules + Frameworks), the gate's
simulator pick uses plain iPhones only, and the main checkout is known only from `IOS_TEAM_MAIN_REPO`.

### Internal links (required once per developer)

Company-internal ids are not in this repo: the Atlassian site and `cloudId`, Confluence page ids, the Jira account id, the TestOps project and the analytics registry sheet. The agents read them from a local file:

1. Copy [`links.example.md`](links.example.md) to `~/.claude/ios-team/links.md`.
2. Fill in the values (ask a teammate who has the file).

Without it, an agent that needs one of these returns `blocked`: «нет ~/.claude/ios-team/links.md — создай его по links.example.md» — the same way as for `project.md`.

### Paths

The main checkout is `main_checkout` in `project.md` (`~` is expanded). `IOS_TEAM_MAIN_REPO` in the `env` block of `~/.claude/settings.json` still overrides it, and `IOS_SH` overrides the `ios_dev_plugin_path` glob.

### Developing the plugin itself

Clone the repo, then load it from the folder with `CLAUDE_CODE_PLUGIN_DIRS=<abs path>` in the `env` block of `~/.claude/settings.json` (plus `CLAUDE_CODE_PLUGIN_DIR_WATCH=1` so running sessions reload on save), and uninstall the marketplace copy first. If you have a personal `~/.claude/skills/pr-description-ru`, remove or rename it, so only `ios-team:pr-description-ru` answers.

## License

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

## Enable it in a project

In your iOS repository's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "ios-team": {
      "source": { "source": "github", "repo": "oleg-kalistratov/ios-team" },
      "autoUpdate": true
    }
  },
  "enabledPlugins": {
    "ios-team@ios-team": true
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
`ios-team:lead` in the main session. Until that row exists, start each session's work
with `/ios-team:lead`: the repo's own worktree row would otherwise steer the session
to create worktrees itself.

## Prerequisites

- **Requires the ios-dev, ios-testing and swiftui-expert plugins enabled (your plugin marketplace or
  the desktop org catalog):** `ios-dev` (`ios.sh`, `sim.sh`, `remove-worktree`), `ios-testing`
  (`test-first`, the Allure TestOps MCP) and `swiftui-expert`. They are deliberately not
  declared as `dependencies` in `plugin.json`: an unsatisfied dependency disables the whole
  plugin — agents, skills and every guard — with no visible error, and the
  desktop's org-catalog copies do not satisfy the CLI dependency check. If one is missing,
  the agents say so in `not_verified` and fall back (no `ios.sh` → the gate reports `infra`).
- `python3` and `jq` on `PATH` (the hook scripts use them).
- `.claude/ios-build.conf` in the main checkout with `TEST_SCHEME="<pr_test_plan>"` (the dev app
  scheme, `dev_scheme`, has no test action); `wt-keeper` copies it into every new worktree.
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
- **Heavy** — `scripts/lease.sh run heavy -- <cmd>`: one unit (`IOS_TEAM_HEAVY_UNITS`) for cold
  builds, tests and `tuist generate`, heartbeat while the command runs, released on exit. Parallel
  sessions queue their builds: on a 16 GB Mac two xcodebuilds plus two simulators swap and both get
  slower than one after the other.
- **QA simulators** — the existing `qa_sims_dev` / `qa_sims_prod` from project.md (the Mac's
  simulator list is the truth; empty sets mean any existing simulator); a new one is created only
  when no existing simulator fits the device class, and the report says so. The brief's simulator is a preference: when another session holds it,
  qa-tester moves to the next free one of the same device class, first in its flavor's set, then in
  the other set, and names the one it used. All of them held → it asks «подождать / забрать».
  Copies made per ticket by 0.3.1 and earlier (`Duo-ABC-123`) are deleted by `scripts/sweep.sh`
  once their worktree is gone (`scripts/ticket-sims.sh <TICKET> list|shutdown|delete` by hand).
- **Disk** — `scripts/disk-check.sh <GB>` exits 3 below the threshold (10 GB before a
  worktree, 8 GB before a build). Below it the agents first run `scripts/sweep.sh` — DerivedData
  whose worktree no longer exists, simulators of tickets without a worktree, simulators without
  a runtime, nothing anyone still uses — and only then stop and ask; user files are never
  touched.

While an agent waits for your answer, the coordinator treats its leases as held even if the
hooks released them at its stop.

## Checking it

```bash
claude plugin validate --strict ./ios-team                 # manifest and hooks files
bash ./ios-team/tests/hooks.test.sh                          # every hook, allowed and blocked; prints PASS n / FAIL m
./ios-team/scripts/check-neutral.sh                          # no project or company names; prints the hits, exit 1
claude --plugin-dir ./ios-team plugin details ios-team       # what loads and its token cost
```

`plugin validate` does not check agent or skill frontmatter; parse it separately (any YAML
parser) after editing an agent.

## Not verified yet

- That a hook's `ask` still shows the dialog under auto and accept-edits modes (it does under
  bypass, which is why every ask turns into a logged allow there) — the first pilot step checks it
  with `git push --dry-run`.
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

**0.3.4** — simulators that exist, or a new one. `qa_sims_dev` / `qa_sims_prod` must name simulators that exist on the Mac
(`xcrun simctl list devices available` is the truth; empty sets mean any existing simulator); when no existing simulator in either set
or in Xcode's list fits the device class, qa-tester may `xcrun simctl create` one (named after its device type) and reports it in
`installed` / `noticed`, so the lead adds it to project.md. Still never `clone`, `rename`, `erase` or `delete` an existing simulator.

**0.3.3** — two fixes from the first measurement after 0.3.0 (10 tickets). The router config keyed on words in the brief,
and «Frameworks/», «Project.swift», «export», «caption» appear in almost every brief (`not_in_scope`, `fragile_ground`, Figma
values), so qa-tester, reviewer and the engineer ran on opus xhigh for two days ($135–158 per ticket against a $4 median
before). `agent-router.example.json` now keys only on the class token the lead writes in the route line — `route: auto — класс
S|M|L[, движок]: …` — S → sonnet medium, M → opus medium, L → opus high, движок → opus xhigh; qa-tester, reviewer and analytics
are forced to sonnet medium; the architect opus high. Copy it over `~/.claude/agent-router.json` again. And wt-keeper still
returned «tuist ещё идёт» as blocked: the Monitor tool returns at once, the turn ends with nothing to do, the stop hook asks for
a result block. New `scripts/wait-for.sh <file> <regex> [max_s]` blocks in the foreground until the line appears (exit 0) or 9
minutes passed (exit 124: call again); wt-keeper and ios-engineer wait with it instead of Monitor.

**0.3.2** — existing simulators only. The lead no longer creates a per-ticket copy (`Duo-ABC-123`) when the shared simulator
is busy: it puts the first free one of `qa_sims_dev` / `qa_sims_prod` in the brief and grants the device permission on that one.
qa-tester treats the brief's simulator as a preference — on a «занят» deny from sim-lease it moves on its own to the next free
simulator of the same device class, then to the other set (a dev build next to the prod app, never touching it), and names the
one it used; `needs_decision` only when every one is held. wt-keeper's removal no longer calls `ticket-sims.sh`; `sweep.sh` still
deletes copies left by earlier versions.

**0.3.1** — a cheaper tester. qa-tester drives through the accessibility tree first (`sim.sh ui`, `tap-label`, `wait-label` /
`wait-gone` / `wait-stable`; idb is installed on the dev Mac now — the prompt said it was not), takes screenshots as evidence after
transitions rather than before every tap, never sleeps longer than 2 s, and falls back to the simulator MCP with the
fresh-screenshot rule only when idb is unavailable (measured: 984 screenshots and 461 sleeps in 7 runs). The lead passes
`scope: small` for class S and M, `normal` only for class L or «проверь все полностью», and `baseline` / `compare` only on Oleg's
«сравни до и после».

**0.3.0** — a shorter pipeline, and the two helper plugins actually in use. The lead classes every change S / M / L from the
diff (≤ ~150 lines in one module → engineer, gate, publisher, QA only for visible UI; up to ~400 lines or two modules → one
review and one QA pass; Frameworks/, Project.swift, engine, navigation, money → the full path), repeats no full pass after a fix
round (QA reruns the failed cases, the reviewer re-checks its own findings), spawns Explore only for class L, and ships push +
PR + the Jira step through one publisher run (`mode: ship`). **Breaking for briefs:** the route line is now `route: auto — <what
the task is>` and the Agent call carries no `model` or `effort`; the agent-router plugin decides from `~/.claude/agent-router.json`
(copy `agent-router.example.json` there: engine → opus xhigh, shared layers / navigation / money / concurrency → opus high,
mechanical and layout-only engineer work → sonnet medium, qa-tester / reviewer / analytics → sonnet, wt-keeper and publisher keep
their own models). The agents' frontmatter no longer pins a model, so the router's choice applies; a hand-written
`route: <model> <effort>` with the matching call is still accepted when Oleg named the model. Why: a week of spawn logs showed the
router routing nothing — every brief carried a hand-written route line it had to keep. For the swift-code-index plugin: the
SubagentStart context now states whether the checkout's Xcode index exists, with the exact `loadIndex` call, and the new
`index-hint.sh` hook (PreToolUse Grep|Bash) stops the first grep for a Swift symbol once per agent or main session when the index
exists, naming the index tools; strings, logs, `.xcstrings` and `Project.swift` greps never match (measured: 3 index calls
against 42 symbol greps in a week).

**0.2.8** — fewer stops with a question (measured over a week: 161 of 503 agent stops ended in a question or a block,
and 70–83 % of a ticket's wall-clock was agents waiting for the answer). New `scripts/sweep.sh`: DerivedData of worktrees
that no longer exist (by `info.plist` or by Xcode's path hash for the nameless package-resolution leftovers), simulators of
tickets without a worktree, simulators without a runtime; wt-keeper, ios-engineer and qa-tester run it before they stop on a
full disk. wt-keeper waits for a running generate instead of returning «tuist ещё идёт», retries a generate once after a
sweep, and removes a worktree with an open PR when the brief carries `unmerged_ok: yes`. ios-engineer copies a missing
`ios-build.conf` itself, returns its questions as one packet after planning the whole change, never re-asks what
`oleg_words`, `architect_decisions` or the new brief field `defaults` already answer, and decides layout values Figma does not
give, names and the simulator on its own (reported in `noticed`). qa-tester retries a build or install once after a sweep and
reports a Figma mismatch as a `fail`, never as a question. The lead forwards an answer Oleg already gave in the ticket, sends
an agent's own defaults back to it, asks only what is left, in one dialog, and writes every answer to the run log.

**0.2.7** — less load, fewer builds. The heavy lease has one unit by default (`IOS_TEAM_HEAVY_UNITS`): parallel
sessions queue their builds instead of running two xcodebuilds plus two simulators into swap on a 16 GB Mac. New
`scripts/ticket-sims.sh <TICKET> list|shutdown|delete`: qa-tester shuts a ticket's own simulator down after every run,
wt-keeper deletes it in the same compound command as the worktree (the shared `sim_prefix*` / `qa_sims_*` ones are never
matched). New `scripts/generate.sh <checkout>`: the full generate through `ios.sh generate` under the heavy lease, which
records the fingerprint `ios.sh build` checks — after a raw `tuist generate` every later gate regenerated the project again
(14 of 24 measured gates, 100–150 s each); the engineer and wt-keeper use it instead of raw tuist. The engineer's round is
now red → green on the red filter → one targeted gate with the build; the separate widened `--no-build` run is gone (one
test build of 3–5 min per round). guard-bash denies `until`/`while … sleep` loops and `sleep` of 60 s or more from any
agent (one engineer waited 80 minutes that way in a week): long commands run in the background and are awaited with Monitor.

**0.2.6** — bypass mode no longer shows any hook dialog: with `permission_mode: bypassPermissions` every
`ask` from the hooks (including self-protection, unparsed or `$VAR` commands, commit-lint and arch-check findings and
Fable spawns, which still asked in 0.2.5) becomes `allow`, in one place (`ask` in `team.py`), and is written to
`~/.claude/ios-team/state/bypass-allowed.jsonl`. Denies are unchanged in every mode. Other modes still ask.

**0.2.0** — generic: no project or company name is left in the repo, and `scripts/check-neutral.sh` (run by the
suite) keeps it that way. Breaking: the coordinator skill is now `lead` (`/ios-team:lead`, `skills/lead`); update the
routing row in your CLAUDE.md. New `project.example.md` → `~/.claude/ios-team/project.md` holds the project's values;
the prompts name its keys as placeholders, and the scripts read it (`project_value` in `team.py`, `proj` in
`scripts/lib/project.sh`): the main checkout (`main_checkout`, `IOS_TEAM_MAIN_REPO` still wins), the repo check for
commit-lint (`github_repo`), the commit pattern (`commit_pattern`, generic default), the dedicated simulators
(`sim_prefix`), the gate's plans, workspace, DerivedData variable and ios.sh glob (`pr_test_plan`, `workspace`,
`derived_data_env`, `ios_dev_plugin_path`; `IOS_SH` still wins). A missing `project.md` never breaks a hook; `gate.sh`
reports `infra`. `links.md` gained an optional `testops` → `jira_integration` line.

**0.1.0** — first version: the coordinator skill (named after the project then), seven agents (ios-engineer,
architect, qa-tester, reviewer, analytics, wt-keeper, publisher), `pr-description-ru`,
classic guard hooks with the word-plus-dialog confirmation model (no prompt parsing, no
token ledger, no shadow mode), simulator/writer/heavy leases, the verification gate
script, and the diagnostic-bundle pre-pass. No `dependencies` in
`plugin.json` (a missing one would silently drop the whole plugin, guards included).
