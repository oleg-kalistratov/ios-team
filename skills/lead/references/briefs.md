# Brief templates — one per agent

Copy the template into the Agent tool's `prompt`. Values in `<angle brackets>` are filled in literally (a placeholder named after a project.md key, such as `<dev_scheme>` or `<github_repo>`, with that key's value): absolute paths, real branch names, Oleg's verbatim words in «». Leave a field as `none` rather than dropping it. A brief is data the agent works from — it carries facts and decisions, never «use your judgement about asking Oleg»: agents never ask him, they return `needs_decision`.

Field names are by meaning: when an agent's own prompt names a field differently, map it — do not drop the content. `${CLAUDE_PLUGIN_ROOT}` is substituted only in SKILL.md and the agents' own instructions, not in this file or in a brief: when a brief must name a script, write the full path as SKILL.md shows it.

Every brief starts with the common header:

```
route: <model> <effort> — <one Russian line why: mechanical / ordinary / risky / engine, and the escalation if any>
ticket: ABC-123 | branch: <type>/ABC-123 | base: <base as Oleg named it> | worktree: <abs path or none> | main: <abs main checkout>
scratch: <your session scratchpad dir> | deadline_min: <n>
```

The `route:` line is mandatory for every ios-team agent (the spawn hook denies a spawn without it) and must match the `model` and `effort` passed to the Agent tool. An escalated run adds `handoff: <scratch>/runs/<ticket>-<role>-handoff.md` and the failing evidence.

Resume with SendMessage — the only resume path (agents cannot message anyone, and a second spawn would redo the work): an answer to its `needs_decision`, a fix after QA, Oleg's correction → `SendMessage(to: <agentId from the result or the spawn>, message: "<his verbatim answer> → <what it decides>; continue from step <n>")`. A relaunch after TaskStop is a new `implement`/`fix` brief that says which uncommitted changes come from the stopped run.

## Change set — what «the diff» means

Nothing is committed before «комить»: the engineer leaves its work in the working tree. So every diff an agent reads, and every diff you read yourself before the commit (the skills check, QA, review, the analytics audit, the architect's diff mode, the tree id), is the working tree against the merge-base, plus new files:

- `mb` = `git -C <wt> merge-base origin/<base> HEAD` (a pilot: its base sha). Compute it for each brief and pass the sha as `diff_base`.
- tracked changes, committed and uncommitted together: `git -C <wt> diff <mb>` (with `--stat`, `--name-status` or `-- '*.swift'` as needed);
- new files: `git -C <wt> ls-files --others --exclude-standard`, each read whole. Always with `--exclude-standard`: without it git lists ignored files, Secrets among them.

`<base>...HEAD` shows only commits, so before the commit it is empty or stale. After the commit, with a clean tree, it equals the change set.

---

## ios-team:ios-engineer — background, opus high

```
<common header>
mode: implement | fix
goal_ru: <one line in Oleg's words: what the user should see or get>
oleg_words: <every exact quote that defines behaviour, names or triggers, e.g. «называть это не onboarding а live photo tutorial»; «когда впервые выбрали live photo»>
plan: <the approved plan, numbered, with file paths; what must not change>
test_first: required | exempt — <the reason Oleg saw and accepted>   (omit = required; exempt only on his word: render-only refactor, tests-only, docs/CI-only)
corner_cases: <T1..Tn from the seven questions (nothing, boundary, error, interrupted, twice at once, old persisted data, other language), each with the expected result>
fragile_ground: <none | the areas where it must return needs_decision instead of guessing: money, concurrency, render/export, keychain, migrations, deeplinks>
skills_required: ios-testing:test-first, code-style-guidance, <every row of the CLAUDE.md skill table this diff will hit: viewmodel-pattern-guidance, swiftui-conventions-guidance, localization-guidance, error-handling-guidance, navigation-guidance, dependency-injection-guidance, project-architecture-guidance, swiftlint-guidance, video-editor-service-guidance>, swiftui-expert:swiftui-expert-skill (SwiftUI work; repo conventions win)
architect_decisions: <decisions[] from the architect result (type_or_file, layer, path, reuse, imports_allowed), or none>
analytics_table: <Событие | Когда | Параметры from the analytics agent, or none>
figma: <node link + the values to use (pt, colors, fonts), or «нет доступа — не угадывать, вернуть needs_decision»>
docs: <repo docs to read; Confluence page ids only when an endpoint is wired (a Backend service page + the common Error page, from `~/.claude/ios-team/links.md`)>
tests: <test targets and the -only-testing filters expected; a new target needs Project.swift + Workspace + both test plans>
gate: gate.sh <worktree> --tests "<filter>" --base HEAD [--plan <nightly_test_plan>] --logs <scratch>/ios-engineer/<ticket>/gate   (the shape only — the agent has the script's full path in its own instructions; red: the new tests fail, run on the new and changed suites only; green: the targeted gate on the task's suites — `<Target>/<Suite>` filters, never a whole `<Target>`; the full suite runs in the PR's CI)
full_gate: <omit | required — only on Oleg's word>
findings: <fix mode only: [{source: reviewer|qa-tester|oleg, file_line, repro, expected, actual}]>
not_in_scope: <what not to touch; side fixes are reported in noticed, not made>
```
Returns `red_run`, `green_run`, `files_changed`, `skills_invoked`. It never commits or pushes. Fable only with `model: "fable"` after Oleg's yes (engine/Metal).

## ios-team:architect — background, opus high, read-only

Only on a structural trigger: new file/type in `Frameworks/`, new module or framework, new `import` or `Project.swift` dependency, new public `CV1Presentation` component, new service or repository, cross-module navigation.

```
<common header>
mode: plan | diff
trigger: <which structural change, in one line>
plan: <plan mode: the coordinator's plan with the new types and their intended paths>
diff_base: <diff mode: <mb> — the change set above>
files: <someone else's PR: the slice's file list>   pr_base: <someone else's PR: origin/<baseRefName>>
checkout: <abs path of the tree to read: the worktree or the scratch checkout>
questions: <the placement questions you want answered, e.g. «где живёт DefaultLivePhotoTutorialService?»>
known_decisions: <memory/ADR entries to respect, e.g. architecture-code-is-truth: Default*Service in CV1Domain/Services/DefaultImpl>
plan_decisions: <diff mode on own work: its decisions from the plan review, or none>
```
Returns `decisions`, `violations`, `adr_entries` (proposed text for `documentation/architecture/decisions.md`; written only on Oleg's word).

## ios-team:qa-tester — background, sonnet high

It derives its own corner cases first and only then reads yours — so put your T-items in a file (`<scratch>/qa/<ticket>/coordinator-cases.md`) and pass the path, not the list inline.

```
<common header>
mode: verify | full | baseline | compare | rerun
scope: small | normal   (small: one behaviour in a few files — coordinator cases + ≤3 own, ~15 min)
what_changed_ru: <plain description of the user-visible change>
ticket_text: <Jira summary + acceptance criteria verbatim, + Oleg's later words that override them>
figma: <node link + key values (pt, colors, fonts), or «нет доступа»>
diff_base: <mb> — the change set above (never <base>...HEAD before the commit)
checklist_ids: <from references/verify-checklists.md: U1, U5, U6, U7 + the area section, e.g. R1–R6; U2–U4 when colours/copy/layout changed; U8 when events changed>
coordinator_cases: <abs path of the file with T1..Tn — it reads it only after deriving its own>
rerun_ids: <rerun mode: only these ids>
before: <compare mode: abs path of the scratch checkout built from the base (the «before» app), or none>
build: <«собери и поставь <dev_scheme> из worktree» | «уже стоит: <dev_scheme> <branch>@<sha>»> — always ios.sh with --simulator, never the production flavor (`prod_bundle_id`)
simulator: <UDID and name | «любой свободный»>
media_wanted: <screenshots | video for the PR | none>
analytics_check: <events with expected params (the analytics agent's qa_handoff) to find in Debug Menu → Local Analytics, or none>
hints: <the <dev_scheme> app only (bundle <dev_bundle_id>, scheme <dev_url_scheme>://); deeplinks; Debug Menu routes and mocks (Profile → About → version ×3, out, in, ×3, shake → Debug Menu); media to seed with `xcrun simctl addmedia <UDID> <files>` — a Live Photo is a still (HEIC/JPEG) + MOV pair sharing one content identifier: the plugin's `scripts/qa/live-photo/seed-live-photo.sh <out dir> <UDID>` makes and adds one, or say that a sample Live Photo is on the simulator; «once per install» keys to reset (terminate, then `plutil -remove <key> <app data container>/Library/Preferences/<dev_bundle_id>.plist` (container from `xcrun simctl get_app_container <UDID> <dev_bundle_id> data`) and launch; the key from files_changed — never uninstall, that hits the login wall); permission resets (`xcrun simctl privacy <UDID> reset photos <dev_bundle_id>`); accounts that are safe to use>
evidence_dir: <scratch>/qa/<ticket>/   (never inside the worktree)
```
Returns `cases_derived`, `cases_run`, `bugs`, `device_only` («нужно устройство»).

## ios-team:reviewer — background, sonnet high, read-only

Correctness only. Layering/imports/placement are the architect's, events are the analytics agent's.

```
<common header>
scope: own | merge-check | pr-slice
checkout: <abs path of the tree to read>
diff_base: <own and pr-slice: <mb> — the change set above>
merge: <merge-check: the merge commit sha (compare both parents)>
files: <pr-slice: the file list, ≤40 files, from `git diff --name-status <mb>` in the checkout or `gh api …/pulls/<n>/files --paginate` — never `gh pr view --json files` (100 max)>
focus: <the seven questions; CLAUDE.md invariants beyond regex; test quality (does each test fail without the fix?); for merge-check: lost hunks in Project.swift, .xcstrings, .xctestplan>
known_decisions: <memory files and Oleg's decisions the code is allowed to follow, e.g. a memory file such as live-photo-tutorial>
pr: <pr-slice only: number, title, author; slice k of n>
goal_ru / corner_cases: <optional for own/merge-check: what the change must do; the engineer's cases and red/green evidence>
```

## ios-team:analytics — background, sonnet high

```
<common header>
mode: question | design | audit | registry_draft | jira_draft   (design already returns the table, registry rows and Jira draft)
question_ru: <Oleg's question verbatim>
feature: <what the user does and where; screens; the triggers in Oleg's words>
diff_base: <audit only: <mb> — the change set above>
existing_events: <names already in code for this area, if you know them>
```
Returns `events_table`, `registry_rows` (exact rows; the sheet write is not verified), `jira_draft` (only the table «Событие | Когда | Параметры»), `audit`. Writes nothing outward.

## ios-team:wt-keeper — haiku (never pass model or effort)

Background for `create`, `scratch` and `sweep-derived-data`; **foreground** for `remove` and `remove-scratch` (their one compound removal command raises one dialog).

```
<common header>
op: create | scratch | remove | remove-scratch | sweep-derived-data
run_from: <abs main checkout>   (start every command with `cd <main> &&` or `git -C <abs>`)
type: feature | bugfix | tech | hotfix | pilot          (create)
base: <branch exactly as Oleg named it; pilot: the exact commit sha>   (create)
target: <abs path, e.g. <dirname main>/<repo_name>-ABC-123; pilot: <dirname main>/<repo_name>-pilot-ABC-123>   (create)
pr: <number>                                            (remove — the coordinator already saw MERGED)
owner_session: <this session's id — the uuid in your scratchpad path>   (remove)
pilot_discard_ok: yes | no                              (remove of a pilot/* branch; yes only from Oleg's word)
discard_files: <the exact paths Worktree listed and Oleg agreed to lose> | none   (remove; only after his explicit answer to that list)
ref: <branch | sha | pull/<n>/head>  build: true|false  name: <short>  (scratch; the checkout goes under <scratch>/; build: true only for this repo's own branches or shas, never a PR head)
```
Returns `worktree`, `branch`, `base`, `base_sha`. It never calls `ccd_*` tools, never deletes user files to make room, never moves untracked files — it lists them and stops.

## ios-team:publisher — foreground, sonnet medium

Spawn only after Oleg's word; quote it. One outward action per word; the dialog is the confirmation.

```
<common header>
mode: push | pr_create | pr_edit | pr_body_draft | ci_status | jira_create | jira_edit | jira_comment | jira_transition | jira_draft | confluence_update | confluence_create | testops_link
oleg_word: «<his exact word>»   (every write mode; without it the publisher only drafts)
pilot: true | false             (a replay of merged work, e.g. pilot/ABC-123: dry run, no outward write)
ticketless_ok: yes | no         (a branch without a ticket key: Oleg's recorded choice)
summary_ru: <your approved report: Проблема / Что сделано / Как проверено (real numbers) / Что не проверено>
media: <abs paths of screenshots/videos for the PR, or none>
pr: <number or URL>   change: <pr_edit: what to change>
jira: {issue: ABC-… | new, type: Задача|Баг|Подзадача, summary: "[iOS] …", bullets: [...] | table: "...", comment: "...", target_status: "...", parent: ABC-…, sprint: current, fix_version: "<x.y.z>-ios", component: "10000"}
page: {id: <confluence page id> | new (space + parent id), title: "...", draft_path: <abs path of the approved draft>, change: "<what to change>"}
testops: {case_id: <id>, issue: ABC-…}
```
Returns `pr_url`, `ci_status`, `jira_key`, `page_url` (and `dry_run: true` in a pilot). `pr_body_draft` and `jira_draft` write only to the scratchpad. It never merges, labels, dispatches workflows, posts reviews or deletes.

## Built-in Explore — quick code map (≤2 in parallel)

`subagent_type: "Explore"`, `model: "sonnet"`, foreground. Prompt: the question, the area paths, «read-only; answer with file:line; under 300 words».
