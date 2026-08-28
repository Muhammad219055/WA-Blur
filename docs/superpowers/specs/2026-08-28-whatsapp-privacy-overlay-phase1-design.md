# WhatsApp Privacy Overlay — Phase 1 Design (Proof of Concept)

Date: 2026-08-28
Repo: `git@github.com-personal:Muhammad219055/WA-Blur.git`
Local path: `~/Developer/WhatsAppPrivacy`

## Goal

Prove, reliably, that we can: detect the official WhatsApp macOS app → identify its
window → track its frame in real time → place a click-through overlay exactly over
it → toggle that overlay globally with ⌘⇧B. Nothing else. This is the foundation
every later phase (blur styles, region-level privacy, reveal gestures, settings UI)
builds on — if this isn't rock solid, nothing built on top of it matters.

Priority order for every decision in this phase: **Reliability > Privacy > Correctness
> Performance > Maintainability > Visual polish.**

## Explicit non-goals for Phase 1

Not implemented yet (deferred to later phases per the full product spec):
message detection, contact-name detection, OCR, individual message blurring,
chat-list/conversation region detection, real blur/pixelation effects, hover/click
reveal, advanced settings UI, persistent user preferences, any network functionality.
The overlay in Phase 1 renders a flat translucent tint + label, not real blur — that
comes in Phase 2.

## Verified environment

- Xcode 26.1.1, Swift 6.2.1, macOS 26.5.2, Apple Silicon (arm64).
- Homebrew present; XcodeGen not yet installed (`brew install xcodegen` required).
- WhatsApp.app installed at `/Applications/WhatsApp.app`.
  - Bundle identifier: `net.whatsapp.WhatsApp` (verified via `PlistBuddy`).
  - Code signing Team Identifier: `57T9237FN3` (Meta), verified via `codesign -dv`.
- Repo `WA-Blur` exists on GitHub under the `Muhammad219055` account, was empty,
  cloned cleanly to `~/Developer/WhatsAppPrivacy`, `origin` remote confirmed, branch
  `main`, zero prior commits — nothing to preserve or reconcile.

## Project tooling

- XcodeGen generates the `.xcodeproj` from `project.yml`. `project.yml` is the
  source of truth; the generated `.xcodeproj` is never hand-edited, and is
  git-ignored (regenerated via `xcodegen generate` after any `project.yml` change,
  or on fresh clone).
- Target: macOS 14+, Swift 6 (strict concurrency), `LSUIElement = true` (menu-bar
  only, no Dock icon). Local ad-hoc/development code signing — no paid Apple
  Developer account required for this phase.
- `.gitignore` excludes: `*.xcodeproj` (generated), `DerivedData/`, `.build/`,
  `.swiftpm/`, `*.xcuserstate`, `xcuserdata/`, `.DS_Store`. Nothing sensitive
  (signing credentials, secrets, WhatsApp data) is ever written to the repo.

## Architecture

Full folder structure from the product spec is created (`App/`, `WhatsApp/`,
`Overlay/`, `Privacy/`, `Permissions/`, `Settings/`, `MenuBar/`, `Diagnostics/`),
but Phase 1 only implements `App/`, `WhatsApp/`, `Overlay/`, `Permissions/`,
`MenuBar/`. Other folders get minimal stubs so the structure is visible; they are
filled in by later phases, not now.

### Data flow

```
WhatsAppDetector (NSWorkspace launch/terminate/activate notifications)
        |
        v
AccessibilityManager session start/stop (per WhatsApp process)
        |
        +--> AXObserver notifications (moved/resized/destroyed/miniaturized/deminiaturized)
        +--> DispatchSourceTimer safety net (only while WhatsApp is running)
        +--> NSApplication.didChangeScreenParametersNotification (display changes)
        |
        v
AXCoordinateConverter (AX frame -> Cocoa screen frame)
        |
        v
WhatsAppWindowTracker.frame (published)
        |
        v
OverlayManager -> single PrivacyOverlayWindow (frame = WhatsApp frame)

GlobalHotkeyManager (Carbon RegisterEventHotKey, ⌘⇧B)
        |
        v
AppState.isPrivacyEnabled toggle -> PrivacyOverlayView show/hide
```

All in-process. No network access. No persistence of anything WhatsApp-related in
Phase 1 (no settings persistence yet either — that's Phase 6).

### Components

**`WhatsAppIdentity`** (`WhatsApp/`) — single source of truth for identifying
WhatsApp. Primary and only *active* matcher: `bundleIdentifier ==
"net.whatsapp.WhatsApp"`. The matching function is structured to allow a
name+team-identifier fallback (`localizedName == "WhatsApp" AND
teamIdentifier == "57T9237FN3"`) to be enabled later if WhatsApp ever changes its
bundle ID, but this fallback ships **disabled** in Phase 1. A name-only fallback
(no team-ID check) is explicitly rejected: for a privacy tool, matching any app
merely titled "WhatsApp" is a false-positive risk (wrong window overlaid, or real
WhatsApp left unprotected while a decoy matches first) that isn't justified when
the bundle ID is confirmed stable today.

**`WhatsAppDetector`** (`WhatsApp/`) — observes `NSWorkspace` running-application
list plus `didLaunchApplicationNotification` / `didTerminateApplicationNotification`
/ `didActivateApplicationNotification`, filtered through `WhatsAppIdentity`. Starts
an `AccessibilityManager` session on launch/already-running, stops it on terminate.

**`AccessibilityManager`** (`Permissions/`) — wraps `AXIsProcessTrustedWithOptions`
for permission check/prompt, and the AX plumbing: `AXUIElementCreateApplication(pid)`
→ `kAXWindowsAttribute` → main window → `kAXPositionAttribute` /
`kAXSizeAttribute`. Registers an `AXObserver` for `kAXMovedNotification`,
`kAXResizedNotification`, `kAXUIElementDestroyedNotification`,
`kAXWindowMiniaturizedNotification`, `kAXWindowDeminiaturizedNotification` on
WhatsApp's window, added to the run loop — event-driven, not polling. If
Accessibility is not trusted, no AX calls are attempted at all (menu bar shows an
onboarding prompt instead); permission state is re-checked on a timer and on
app-activate so the app self-heals the moment the user grants it in System
Settings.

**Safety-net mechanism** — a `DispatchSourceTimer` (not a plain `Timer`), ~1s
interval with ~300-500ms leeway so the OS can coalesce the wakeup with other system
timer activity. Created only when `WhatsAppDetector` reports WhatsApp running,
cancelled immediately on termination or on Accessibility trust being revoked —
never active when WhatsApp isn't open. Supplemented by
`NSApplication.didChangeScreenParametersNotification` as an event-driven trigger
for display-configuration changes (monitor added/removed/resolution changed),
since AX doesn't reliably fire a moved/resized notification purely from screen
geometry changing under a stationary window.

**`AXCoordinateConverter`** (`WhatsApp/`) — dedicated, isolated, unit-testable
component converting AX's global top-left-origin, Y-down coordinate space into
Cocoa's global bottom-left-origin, Y-up space. The two spaces describe the same
combined multi-display area and differ only by a single Y flip anchored at the
**primary (menu-bar) screen's height** (`NSScreen.screens[0]`, which AppKit
guarantees is the menu-bar display) — not a per-window "nearest screen" flip, and
not something that varies with how many displays exist or how they're arranged
(left/right/above/below, negative origins). Retina/backing-scale-factor is
explicitly *not* part of this function: AX and Cocoa frames are both already in
points, and AppKit assigns the overlay window's backing scale automatically from
whichever screen it mostly occupies.

```swift
enum AXCoordinateConverter {
    // Pure core, no NSScreen dependency (NSScreen has no public initializer,
    // so synthetic multi-monitor arrangements can't be constructed in tests
    // any other way).
    static func cocoaFrame(fromAXFrame axFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect

    // Thin production wrapper.
    static func cocoaFrame(fromAXFrame axFrame: CGRect, screens: [NSScreen] = NSScreen.screens) -> CGRect?
}
```

Unit tests exercise the pure function against several synthetic arrangements
(secondary display right/left/above/below primary, negative origins, differing
secondary resolutions) and explicitly assert that varying *secondary*-screen
geometry never changes the result for a fixed `axFrame`/`primaryScreenHeight` —
that invariant is the actual thing worth locking down.

**`WhatsAppWindowTracker`** (`WhatsApp/`) — glue layer; consumes AX notifications,
the safety-net timer, and screen-change notifications, runs frames through
`AXCoordinateConverter`, and publishes the current WhatsApp window frame
(`@Published`) for the overlay to consume.

**`OverlayManager` / `PrivacyOverlayWindow` / `PrivacyOverlayView`** (`Overlay/`) —
**one** borderless `NSWindow` (not one per screen — AppKit natively supports a
single window frame spanning multiple physical displays, the same way any ordinary
window can be dragged half onto a second monitor; per-screen windows would only be
justified by a future need for independent per-monitor rendering, which doesn't
apply yet). `.floating` level, `isOpaque = false`, `backgroundColor = .clear`,
`ignoresMouseEvents = true`, `collectionBehavior` includes `.canJoinAllSpaces`,
`.fullScreenAuxiliary`, `.stationary`. Frame is set directly from
`WhatsAppWindowTracker.frame`. `PrivacyOverlayView` renders a translucent tint +
"PRIVACY ON" label (proof of alignment/toggle only — real blur is Phase 2). Window
is destroyed when WhatsApp closes, hidden/shown based on `AppState.isPrivacyEnabled`.

**`GlobalHotkeyManager`** (`MenuBar/` or `App/`) — registers ⌘⇧B via Carbon's
`RegisterEventHotKey`/`UnregisterEventHotKey`, chosen over `NSEvent` global
monitoring for two concrete reasons: (1) Secure Input Mode suppresses `keyDown`
delivery to `NSEvent` global monitors system-wide whenever any secure text field
has focus, but registered Carbon hotkeys keep firing (the same mechanism Spotlight
and the screenshot hotkey rely on); (2) Carbon registration genuinely intercepts
the combination system-wide rather than merely observing it, so it doesn't also
let the frontmost app's own menu equivalent fire (⌘⇧B is Safari's Bookmarks Bar
toggle). Implemented as a top-level `@convention(c)` handler function plus a
MainActor-isolated hotkey-ID registry (Carbon's C callback can't capture Swift
context directly) — hand-rolled rather than adding a dependency. Fully decoupled
from Accessibility trust; AX permission remains required only for WhatsApp window
tracking, not for the hotkey.

**`AppState`** (`App/`) — small `ObservableObject`: `isPrivacyEnabled`,
`isWhatsAppRunning`, `whatsAppFrame`, `accessibilityTrusted`.

**Menu bar UI** (`MenuBar/`) — SwiftUI `MenuBarExtra`, `NSApplicationDelegateAdaptor`
for AX/permission lifecycle wiring. Shows "Waiting for WhatsApp…" when not running
(no error dialog), an onboarding prompt with an "Open System Settings" button
(deep-links to Privacy & Security → Accessibility) when permission is missing, and
current privacy on/off state when running normally.

## Error handling

- No Accessibility permission → no AX calls attempted, overlay never created, menu
  bar shows onboarding; state re-checked on timer + app-activate.
- WhatsApp not running → "Waiting for WhatsApp…", no error dialog.
- AX call failures (window vanished mid-read, etc.) → treated as "no frame this
  tick," skipped, never force-unwrapped.

## Phase 1 acceptance criteria

Phase 1 is not complete merely because the project builds or launches. Every item
below must be checked off, and each must be labeled one of: **Verified
automatically**, **Verified manually**, **Not yet verified**, or **Known
limitation** — never claimed done because the code "looks correct."

- [ ] App launches as a menu-bar-only application
- [ ] No Dock icon is shown
- [ ] WhatsApp is detected when it is already running
- [ ] WhatsApp is detected when it is launched after our app
- [ ] WhatsApp termination is detected
- [ ] Accessibility permission state is correctly detected
- [ ] App provides appropriate onboarding when Accessibility permission is missing
- [ ] WhatsApp's main window is identified
- [ ] Overlay matches the WhatsApp window frame
- [ ] Overlay follows WhatsApp when the window moves
- [ ] Overlay follows WhatsApp when the window resizes
- [ ] Overlay disappears when WhatsApp closes
- [ ] Overlay does not intercept normal WhatsApp mouse interaction
- [ ] Overlay works correctly with Retina scaling
- [ ] Overlay works correctly when WhatsApp is moved between displays
- [ ] ⌘⇧B works as a global shortcut
- [ ] ⌘⇧B toggles privacy state
- [ ] Overlay visibility follows privacy state
- [ ] No unnecessary high-frequency polling occurs
- [ ] CPU usage remains reasonable while idle
- [ ] App handles WhatsApp window disappearance without crashing
- [ ] AX failures are handled gracefully

Do not proceed to Phase 2 until this list is worked through as far as technically
possible, with honest labeling of what couldn't be verified and why.

## Testing approach

- **Unit tests**: `AXCoordinateConverter` pure-function math across synthetic
  multi-monitor arrangements; `WhatsAppIdentity` matching logic against fake
  `NSRunningApplication`-shaped fixtures (bundle ID match/no-match; fallback stays
  inactive by default).
- **Manual/visual verification**: launch WhatsApp and the app, grant Accessibility
  permission when prompted (the one step that needs a human click in System
  Settings — cannot be automated), then use `screencapture` + image inspection to
  confirm overlay-to-WhatsApp alignment while moving/resizing/switching displays,
  and confirm ⌘⇧B toggles visibility. Findings reported against the acceptance
  criteria list above with explicit verification-method labels.

## Git workflow

Milestone-based commits only (no dozens of trivial commits):

```
Phase 1: project scaffolding
Phase 1: WhatsApp detection
Phase 1: accessibility/window tracking
Phase 1: overlay implementation
Phase 1: global hotkey
Phase 1: coordinate conversion/tests
Phase 1: final stabilization
```

`git status`/`git diff`/`git log` inspected before every push. No force-push. No
build artifacts, `DerivedData`, `.DS_Store`, user-specific Xcode state, secrets,
signing credentials, or WhatsApp-derived data ever committed.
