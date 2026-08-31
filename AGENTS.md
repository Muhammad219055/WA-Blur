# Agent guide — WhatsApp Privacy Overlay

Read this before touching code in this repo, whatever tool you are. It
distills two things: the working discipline that has actually caught real
bugs in this project (not generic advice — every rule below exists because
skipping it once already cost time), and the project-specific traps a
fresh agent will otherwise rediscover the hard way.

## What this project is

A native macOS menu-bar utility that draws a click-through privacy overlay
over the real WhatsApp desktop app — it never modifies WhatsApp itself. See:

- `docs/superpowers/specs/2026-08-28-whatsapp-privacy-overlay-phase1-design.md` — the product spec
- `docs/superpowers/plans/2026-08-28-whatsapp-privacy-overlay-phase1.md` — Phase 1 plan + acceptance results
- `docs/superpowers/plans/2026-08-28-whatsapp-privacy-overlay-phase2.md` — Phase 2 plan (styles, Space fix, capture pipeline)

Before starting new work, check whether a plan already covers it. If not,
write one (spec → plan → tasks) before writing code — see "Plan before you
build" below. Don't skip this because the change looks small; several of
the bugs in this project's history came from small, unplanned edits to
`AppDelegate.swift` that didn't account for an interaction another part of
the file depended on.

## Plan before you build

For anything beyond a one-line fix: write down what you're building and why
*before* writing code. A short plan that lists the files you'll touch, the
interfaces they expose, and how you'll verify each piece — committed to
`docs/*/plans/` — catches design mistakes when they cost one paragraph to
fix, not a rewrite. Skipping this for "it's obvious" tasks is exactly when
it bites: the cross-Space overlay leak (see Known traps below) came from a
one-line `collectionBehavior` change that looked obviously correct and
wasn't tested against the actual failure mode until a user hit it live.

## Verification discipline — the single most important rule here

**Never claim something works because the code looks correct. Claim it
works because you ran it and watched it work.**

This project's plans use four labels for every acceptance item, and so
should you when reporting status:

- **Verified automatically** — covered by a passing automated test, named.
- **Verified manually** — you personally ran the app and observed the
  behavior *in this session*, not "it worked earlier" or "the previous
  version did this."
- **Not yet verified** — you didn't check. Say so. Don't imply otherwise.
- **Known limitation** — checked, confirmed not working, and out of scope
  to fix right now. Say why.

A build succeeding is not verification that a feature works. This project
hit multiple bugs (the cross-Space leak, the minimize-doesn't-hide bug, the
suppression-logic bug that leaked the overlay onto a different desktop)
that compiled cleanly, passed all unit tests, and were still wrong — they
only surfaced by actually running the app against the real WhatsApp window
and watching what happened. When you fix something, re-verify the *exact*
scenario that was reported broken, not just that the code compiles.

If you cannot run a live check (no display, no WhatsApp installed, etc.),
say exactly that — "Not yet verified: no way to launch a GUI app in this
environment" — rather than inferring success from the diff looking right.

## No placeholders, no vague steps

Every function must be real, working code — no `// TODO`, no `fatalError("not implemented")`
left in as a stopgap, no "add appropriate error handling" comments standing
in for actual guards. If a task is too big to finish now, do a smaller
complete piece rather than a larger incomplete one.

## Build and test — the commands that matter

`project.yml` is the source of truth for the Xcode project, not the
`.xcodeproj` (which is generated and git-ignored). After creating or
renaming any file:

```bash
xcodegen generate
xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30
xcodebuild test -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -destination 'platform=macOS' 2>&1 | tail -20
```

**Trust `xcodebuild`'s actual output over your editor's inline diagnostics.**
SourceKit/LSP diagnostics in an editor with no live Xcode session attached
routinely show stale false-positive errors ("cannot find type X in scope")
for code that compiles fine — confirmed repeatedly in this project. If the
editor shows red squiggles but `xcodebuild build` says `** BUILD SUCCEEDED **`,
the real build is correct; don't "fix" code to satisfy a stale index.

## Known traps in this codebase

Each of these was a real bug, found by running the app, not by reading the
code. Don't reintroduce them.

- **`@MainActor` on stored-property initializers.** A class holding a
  stored property whose default value is another `@MainActor`-isolated
  type's initializer must itself be `@MainActor`, or Swift 6 strict
  concurrency rejects it at compile time ("main actor-isolated default
  value in a nonisolated context"). `AppDelegate` and every manager class
  in this project are `@MainActor` for exactly this reason — keep new
  ones consistent.
- **AX coordinates vs. Cocoa coordinates.** `AXCoordinateConverter` exists
  because AX/CoreGraphics global coordinates (top-left origin, Y-down) and
  Cocoa coordinates (bottom-left origin, Y-up) differ by a single Y flip
  anchored at the *primary* screen's height (`NSScreen.screens[0]`) — never
  per-window, never scale-factor-adjusted (both spaces are already in
  points). Route any new AX-frame-to-window-frame conversion through this
  type; don't hand-roll another flip.
- **Overlay window Space attachment.** `orderOut()` followed later by
  `orderFront()`/`orderFrontRegardless()` on the *same* window can cause
  AppKit to reattach it to whichever Space is active *at the moment of the
  later call*, not the Space it was created on — there is no public API to
  target a specific background Space directly. `OverlayManager` hides via
  `alphaValue` (never `orderOut`) for same-Space suppression, and only
  drops + recreates the window (`invalidateForSpaceChange`) when
  `NSWorkspace.activeSpaceDidChangeNotification` fires and the correct
  Space is confirmed active. Follow this pattern for any future overlay
  windows; don't reach for `orderOut`/`orderFront` cycling to hide/show one.
- **`.floating` vs `.normal` + relative ordering.** WhatsApp's own window
  can be re-raised far more often than clicks or app-switches (a
  hover-to-raise utility re-raises it continuously from mouse movement
  alone) — there's no notification to react to that in time, so `.normal`
  level + `order(.above, relativeTo:)` produces a constant, visible
  flicker. `.floating` is structurally immune to this (always above every
  `.normal` window, full stop); the tradeoff (sitting above *any* app's
  window) is handled separately by hiding the overlay when a genuinely
  overlapping window becomes frontmost (`WindowStackingLookup` +
  `refreshSuppression` in `AppDelegate`).
- **`refreshSuppression`'s "can't determine bounds" fallback.** When
  WhatsApp's own window can't be found on the *currently active* Space at
  all (the user switched to a different desktop), the correct response is
  to touch nothing and let the Space-change handler own the decision — not
  to fall through to "default not suppressed," which force-creates a
  visible overlay on whatever Space happens to be active. If you touch
  this method again, keep the early-return guard for "WhatsApp's own frame
  isn't findable right now" separate from the "the *other* app's frame
  isn't findable" fallback — they need different defaults.
- **Minimize doesn't fail AX reads.** A minimized window still reports
  valid position/size via AX — minimizing does not make attribute reads
  fail. Detecting "minimized" requires explicitly checking
  `kAXMinimizedAttribute`, not inferring it from a read failure.
- **Ad-hoc code signing breaks Accessibility/Screen-Recording permission
  persistence across rebuilds** on this macOS version — TCC's grant can get
  keyed to the binary's changing ad-hoc signature. `project.yml` uses a
  locally-generated, self-signed certificate (`WhatsAppPrivacy Local Dev`,
  already in this machine's login keychain) instead, specifically because
  its identity is stable across rebuilds. Don't switch back to `"-"` ad-hoc
  signing. If you're setting this up on a different machine, the cert
  generation steps are documented inline in `project.yml`.
- **NSVisualEffectView really does blur other apps' windows.** Confirmed
  empirically, not assumed: `NSVisualEffectView` with `blendingMode =
  .behindWindow` composites a genuine blur of whatever is behind the
  *window*, including other processes' content, at the compositor level —
  the same mechanism the menu bar and Control Center use. If you're
  building another privacy-render style, check whether the compositor can
  do it before reaching for screen capture (`WhatsAppWindowCapture` /
  ScreenCaptureKit) — capture is real overhead and a second TCC permission
  that most styles don't need.

## Working in parallel (the pattern this repo already uses)

Phase 1 and Phase 2 were both built by splitting the plan's tasks across
this session and a second agent (Antigravity), working in **separate git
worktrees** so neither could clobber the other's files. If you're picking
up a task that was handed to you this way:

- You'll find a `TASK_BRIEF.md` in your worktree root — it is the complete,
  self-contained spec for your task. Follow it exactly; don't implement
  anything else from the wider plan.
- Stay inside your assigned files. Tasks in this repo are deliberately
  scoped to be file-disjoint from whatever's running in parallel — if your
  brief says "do NOT touch `AppDelegate.swift`," that's not a suggestion:
  another task (or a later integration pass) owns that file, and touching
  it will produce a merge conflict or silently clobber unrelated work.
- Commit only to your own branch. Never push, merge, or touch `main`
  yourself — a separate integration task does that after independently
  verifying every parallel branch.
- Delete the `TASK_BRIEF.md` as part of your final commit — it's scratch
  instructions, not part of the codebase.
- When you report back, use the verification labels above. "Build
  succeeded" is not the same claim as "I ran the app and confirmed X."

## Git discipline

- One commit per completed task/milestone, not per file or per edit.
  Commit messages explain *why*, not just *what* — several commits in this
  repo's history are long because the reasoning behind a fix (a race
  condition, a coordinate-space gotcha) is exactly what stops the same bug
  from being reintroduced later.
- Never commit build artifacts, `DerivedData/`, `.DS_Store`, signing
  private keys, or anything from `WhatsAppPrivacy/Info.plist` (generated —
  see `.gitignore`).
- Inspect `git status` / `git diff` before every commit. Never force-push.

## Privacy constraints (non-negotiable, not just style)

No network access. Never read, log, or persist WhatsApp message content,
contact names, or screenshots of WhatsApp's content. The overlay is purely
visual — it must never become a way to inspect what it's covering.
