# QA checklists — the floor for qa-tester, not the ceiling

Stable item ids. The coordinator puts the ids that apply into the qa-tester brief (`checklist_ids`) and adds the ticket's own corner cases as T1, T2, … The qa-tester first derives its own cases from the ticket, the acceptance criteria, the Figma values and the diff (ids Q1, Q2, …), then reads this list and the coordinator's T-items, merges the three, and runs everything. An item is done only with a verdict (`pass | fail | blocked | нужно устройство`) and evidence (a screenshot, a frame, a log line or a measured number). Measured against Figma values in pt, never «на глаз». Evidence goes to `<scratch>/qa/<ticket>/`, never into the worktree. `<dev_scheme>`, `<dev_bundle_id>` and `<prod_bundle_id>` are values from `~/.claude/ios-team/project.md`.

**Draft — Oleg reviews each section once during the pilot.**

## Universal (every UI ticket)
- U1 <dev_scheme> built from this worktree is installed; the evidence names branch@sha. Never the production flavor (`<prod_bundle_id>`) (it hits the real paywall).
- U2 Light and dark appearance of the changed screen — when colours, materials or images changed. Switch with `xcrun simctl ui <UDID> appearance dark|light` and restore the original value afterwards.
- U3 Russian and one more catalog language (en, es, pt-BR, de, fr, it): nothing truncated, no raw keys — when copy or layout changed. Use launch arguments (`-AppleLanguages (ru)`), not the simulator's global settings.
- U4 A large Dynamic Type size: no clipping, no overlap — when layout changed. `xcrun simctl ui <UDID> content_size <size>`, restored afterwards.
- U5 The keyboard never covers the active input («поле не поднимается над клавой»).
- U6 No purchase sheet, Apple ID sheet or real send to a third party was reached.
- U7 Kill and relaunch: what should persist persists, what should reset resets.
- U8 Analytics: each event the ticket adds or changes appears once, with the right parameters, in Debug Menu → Local Analytics — when the brief lists `analytics_check`.

## Chat / Omni agent (the video editor, Variants)
- C1 Send a text message; the reply arrives.
- C2 The typing bubble turns into the reply with no jump (the bubble morph; record a video, cut a frame sheet).
- C3 Voice input start and stop.
- C4 Attach media; the original upload completes (`[OriginalUpload]` in the log).
- C5 The credit gate shows the paywall and closes without a purchase.
- C6 Full path: agent render → export → Save → camroll badge; then open the share sheet only (WhatsApp/TikTok targets are listed, nothing is sent). A past bug showed up only on this path.

## Camroll
- R1 Photos permission full and limited.
- R2 First-ever Live Photo selection → the format question (as image / as video) → the live photo tutorial, once per install. Opening the camroll without picking a Live Photo does not consume it. Simulator: seed a Live Photo with `xcrun simctl addmedia <UDID> <still> <mov>` — a still (HEIC or JPEG) and a MOV that share one content identifier (`scripts/qa/live-photo/seed-live-photo.sh <out dir> <UDID>` in the plugin), or a sample photo the simulator library already shows with the LIVE badge; check the badge first. «Once per install» on a simulator that already ran the app: reset the key from `hints` (terminate, then `plutil -remove <key> <app data container>/Library/Preferences/<dev_bundle_id>.plist` (container from `xcrun simctl get_app_container <UDID> <dev_bundle_id> data`) and launch), never uninstall (login wall). A real camera Live Photo → «нужно устройство».
- R3 The format question follows «session = one opening of the camroll» (Figma sticky note, the live-photo memory file): check a second pick in the same opening and a pick after reopening against the ticket's expected behaviour — if the ticket does not say, report it as a question, do not invent the expectation.
- R4 The app's badge on a freshly saved video without restarting the app.
- R5 Duration limits and the premium banner.
- R6 Thumbnails scroll without visible stalls on 200+ items (`simctl addmedia`).

## Edit tools (the edit-tools module / EditorKit / TimelineKit)
- E1 Each touched tool opens, applies, cancels and undoes.
- E2 The timeline stays in sync with the preview after each action.
- E3 Long-press does not reorder clips by accident.
- E4 Captions: add, edit, delete, other-language text.
- E5 Rotation and safe areas on the smallest supported device.

## Paywall / wallet / subscription / cancellation
- P1 Opens from each entry point the ticket touches; closes with the close control only.
- P2 Wallet chip and card states (empty, low, subscribed) match the design values.
- P3 Cancellation screens in order; no real cancellation is sent.
- P4 The Remote Config / experiment variant shown is the one the ticket names (say which).

## Engine / timeline / preview performance
- G1 Playback, scrub and pause on a multi-clip project.
- G2 Export completes; frame parity against the «before» build (`compare` mode, PSNR numbers).
- G3 The simulator cannot play the video → «нужно устройство»; the coordinator runs the device log check.
- G4 The probe counters the ticket names (redraws, writes) before vs after, with numbers.

## Auth / funnel / deeplinks (DDL)
- A1 The deeplink opens the target screen from a cold start and from a warm start (`simctl openurl`).
- A2 Sign-in error states shown without typing real credentials (mock or test backend only).
- A3 Deferred deeplinks need a fresh install — say so if not exercised.

## Onboarding / splash / What's New
- O1 A fresh install shows the flow once; a relaunch does not repeat it.
- O2 Copy in six languages on each changed screen (Onboarding has no test target — this is the only check).
- O3 ATT/IDFA prompts → «нужно устройство».
