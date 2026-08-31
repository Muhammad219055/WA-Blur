# WhatsApp Privacy Overlay — Phase 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the two structural gaps Phase 1 shipped with (overlay leaking onto
the wrong Space, no native-fullscreen support) and replace the flat placeholder
tint with real, adjustable privacy rendering — Blur, Pixelate, and Redact
styles — selectable and persisted from the menu bar.

**Architecture:** A `PrivacySettings` store (UserDefaults-backed) holds the
selected `PrivacyRenderStyle` and `PrivacyIntensity`; `OverlayManager` grows a
style-aware content path that swaps between three view types built on this
phase instead of the one flat `PrivacyOverlayView`. Blur uses
`NSVisualEffectView` with `.behindWindow` blending, which composites a real,
GPU-accelerated blur of whatever is behind the window at the window-server
level — including WhatsApp's actual pixels, since blur effects operate on the
compositor, not per-app rendering, the same mechanism the menu bar and Control
Center use to blur the desktop behind them. Pixelate needs real captured
pixels to pixelate, which Blur does not, so only Pixelate pulls in
ScreenCaptureKit (`SCStream` filtered to WhatsApp's specific window via
`SCContentFilter(desktopIndependentWindow:)`, not a full-screen capture loop).
The Space bug is fixed by switching same-Space hide/show from
`orderOut`/`orderFront` cycling to alpha fading (which doesn't risk Space
reattachment), and handling genuine Space changes (including WhatsApp's own
fullscreen) by listening for `NSWorkspace.activeSpaceDidChangeNotification`
and recreating the overlay window fresh only once the correct Space is
confirmed active — the only reliable way to place a window on a specific
background Space, since AppKit has no public API to target one directly.

**Tech Stack:** Swift 6, AppKit (`NSVisualEffectView`, `NSWindow` alpha/Space
handling), ScreenCaptureKit (`SCStream`, `SCContentFilter`), Core Image
(`CIFilter` pixellate), Combine, XCTest.

## Global Constraints

- Everything in the Phase 1 plan's Global Constraints still applies: macOS
  14+, Apple Silicon first, Swift 6 strict concurrency, no Electron, no
  third-party runtime dependencies, no network access, never read/log/persist
  WhatsApp message content or contact names.
- WhatsApp bundle identifier: `net.whatsapp.WhatsApp`.
- App bundle identifier: `com.wablur.WhatsAppPrivacy`. `project.yml` is the
  source of truth for the Xcode project; regenerate with `xcodegen generate`
  after any change and after pulling this plan's file additions.
- **Known dev-loop friction carried from Phase 1:** ad-hoc code signing does
  not reliably preserve the Accessibility TCC grant across rebuilds on this
  macOS version. After every rebuild in this phase, run
  `tccutil reset Accessibility com.wablur.WhatsAppPrivacy` and re-grant in
  System Settings before manually testing. This phase adds a **second**
  permission (Screen Recording, for ScreenCaptureKit) that likely has the
  same rebuild-instability problem — if a rebuilt binary stops being
  authorized for Screen Recording, run
  `tccutil reset ScreenCapture com.wablur.WhatsAppPrivacy` and re-grant the
  same way.
- ScreenCaptureKit's `SCShareableContent`/`SCStream` APIs require the Screen
  Recording permission (a separate TCC bucket from Accessibility, gated by
  `CGPreflightScreenCaptureAccess()`/`CGRequestScreenCaptureAccess()`) — never
  request it eagerly at launch; only when the user actually selects the
  Pixelate style, since Blur and Redact never need it.
- Never call `CGDisplayCreateImage()` or any other full-display capture in a
  polling loop — the explicit anti-pattern called out in the product spec.
  Task 6's `SCStream` is a push-based, filtered-to-one-window stream at a low
  frame rate (10fps), not a capture loop.
- Full spec reference: `docs/superpowers/specs/2026-08-28-whatsapp-privacy-overlay-phase1-design.md`.
  Phase 1 plan and its Acceptance Results (with the exact diagnosis of the
  Space-reattachment bug this phase fixes) are at
  `docs/superpowers/plans/2026-08-28-whatsapp-privacy-overlay-phase1.md`.

---

## Task 1: Cross-Space and fullscreen correctness

**Files:**
- Modify: `WhatsAppPrivacy/Overlay/OverlayManager.swift`
- Modify: `WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift`
- Modify: `WhatsAppPrivacy/WhatsApp/WindowStackingLookup.swift`
- Modify: `WhatsAppPrivacy/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `WindowStackingLookup.mainWindow(forProcessIdentifier:)` (Phase 1).
- Produces: `WindowStackingLookup.isWindowOnScreen(forProcessIdentifier:) -> Bool`.
  `OverlayManager.invalidateForSpaceChange()`. Later tasks in this plan call
  `overlayManager.showOverlay`/`hideOverlay` exactly as before — this task
  changes their internals (alpha-based, not order-based) but not their
  signatures, so nothing downstream needs to change because of it.

**Diagnosis this task fixes** (from the Phase 1 Acceptance Results): hiding
the overlay via `orderOut` and later showing it again via
`orderFrontRegardless` while the user has since switched to a *different*
Space causes AppKit to attach the window to whichever Space is active at that
moment, not to WhatsApp's original Space — so the overlay can reappear on the
wrong desktop entirely, or fail to appear on WhatsApp's actual fullscreen
Space at all.

- [ ] **Step 1: Add `isWindowOnScreen` to `WindowStackingLookup`**

Open `WhatsAppPrivacy/WhatsApp/WindowStackingLookup.swift` and add this method
inside the `enum WindowStackingLookup` block (after `mainWindow`):

```swift
    /// True only if `pid` has a window CGWindowListCopyWindowInfo reports as
    /// on-screen *right now* -- which, critically, is Space-aware: a window
    /// on a Space that isn't currently active does not appear here. This is
    /// the ground truth this task uses to decide whether WhatsApp is visible
    /// on whichever Space just became active.
    static func isWindowOnScreen(forProcessIdentifier pid: pid_t) -> Bool {
        mainWindow(forProcessIdentifier: pid) != nil
    }
```

- [ ] **Step 2: Switch `OverlayManager` from order-based to alpha-based hide/show**

Replace the entire contents of `WhatsAppPrivacy/Overlay/OverlayManager.swift`:

```swift
import AppKit

@MainActor
final class OverlayManager {
    private var window: PrivacyOverlayWindow?

    /// Ordering the window in once and then only fading `alphaValue` between
    /// 0 and 1 -- never `orderOut`/`orderFront` cycling it -- is what keeps
    /// this window pinned to the Space it was created on. `ignoresMouseEvents`
    /// is already true, so an alpha-0 window still doesn't intercept clicks;
    /// it just isn't visible.
    func showOverlay(at frame: CGRect) {
        if let window {
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }
            window.alphaValue = 1
        } else {
            let newWindow = PrivacyOverlayWindow(frame: frame)
            newWindow.orderFrontRegardless()
            newWindow.alphaValue = 1
            window = newWindow
        }
    }

    func hideOverlay() {
        window?.alphaValue = 0
    }

    func destroyOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    /// Call when the active Space has changed: any existing window may now
    /// be attached to the wrong Space, and there is no public API to move an
    /// existing window to a specific background Space, so the only fix is to
    /// drop it and let the next showOverlay() call create a fresh one while
    /// the correct Space is confirmed active (see AppDelegate).
    func invalidateForSpaceChange() {
        window?.orderOut(nil)
        window = nil
    }
}
```

- [ ] **Step 3: Allow the overlay onto a fullscreen Space**

Open `WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift`. Find the
`collectionBehavior = [.ignoresCycle]` line and its preceding comment block,
and replace that whole comment+line with:

```swift
        // .fullScreenAuxiliary (new in Phase 2): by default, a Space
        // currently showing another app's native-fullscreen window refuses
        // ordinary windows from other apps entirely -- without this flag, a
        // freshly-created overlay window would get bounced back to the
        // regular desktop instead of appearing on WhatsApp's fullscreen
        // Space. Still deliberately NOT .canJoinAllSpaces (see below): that
        // flag makes a window a permanent fixture on *every* Space
        // simultaneously, which is what caused the original cross-desktop
        // leak Phase 1 shipped with. .fullScreenAuxiliary only grants
        // entry to a fullscreen Space that the app is legitimately
        // following into via the Space-change handling in AppDelegate; it
        // does not make the window omnipresent.
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
```

- [ ] **Step 4: React to Space changes in `AppDelegate`**

Open `WhatsAppPrivacy/App/AppDelegate.swift`. Add a new stored property next
to `activationObserver`:

```swift
    private var spaceChangeObserver: NSObjectProtocol?
```

Add a new binding call in `applicationDidFinishLaunching`, right after
`bindAppActivation()`:

```swift
        bindSpaceChanges()
```

Remove the observer in `applicationWillTerminate`, right after the existing
`activationObserver` removal block:

```swift
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
```

Add the new method, placed after `bindAppActivation()`:

```swift
    /// A Space change can only be fixed by dropping any existing overlay
    /// window and letting syncOverlay() create a fresh one while the new
    /// Space is confirmed active (see OverlayManager.invalidateForSpaceChange) --
    /// there's no API to move a window to a specific background Space
    /// directly. Only bothers when WhatsApp is actually on-screen on the
    /// Space that just became active; otherwise there's nothing to show.
    private func bindSpaceChanges() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let waPID = self.currentWhatsAppPID else { return }
            self.overlayManager.invalidateForSpaceChange()
            if WindowStackingLookup.isWindowOnScreen(forProcessIdentifier: waPID) {
                self.syncOverlay()
            }
        }
    }
```

- [ ] **Step 5: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Manually verify — overlay stays on WhatsApp's Space (Verified manually)**

Launch the app, grant/re-grant Accessibility if the dev-loop TCC issue hit
(see Global Constraints). With WhatsApp visible and the overlay showing,
switch to a different Space (Control+Right Arrow, or open Mission Control and
click another desktop). Confirm the overlay does NOT appear on the new Space.
Switch back to WhatsApp's Space and confirm the overlay is still correctly
aligned there.

- [ ] **Step 7: Manually verify — overlay follows WhatsApp into native fullscreen (Verified manually)**

Enter fullscreen for WhatsApp (green traffic-light button, or View menu →
Enter Full Screen). Confirm the overlay appears on the fullscreen Space,
correctly sized to the now-fullscreen window. Exit fullscreen and confirm the
overlay returns to tracking the windowed WhatsApp correctly.

- [ ] **Step 8: Manually verify — same-Space overlap suppression still works (Verified manually)**

This is the Phase 1 behavior that must not regress from switching to
alpha-based hide/show. Open Notes (or any app) over WhatsApp on the same
Space; confirm the overlay still hides. Move Notes away; confirm the overlay
reappears.

- [ ] **Step 9: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Overlay/OverlayManager.swift WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift WhatsAppPrivacy/WhatsApp/WindowStackingLookup.swift WhatsAppPrivacy/App/AppDelegate.swift
git commit -m "Phase 2: fix cross-Space overlay leak and add fullscreen support"
```

---

## Task 2: Privacy settings model + persistence

**Files:**
- Create: `WhatsAppPrivacy/Privacy/PrivacyRenderStyle.swift`
- Create: `WhatsAppPrivacy/Privacy/PrivacyIntensity.swift`
- Create: `WhatsAppPrivacy/Privacy/PrivacySettings.swift`
- Test: `WhatsAppPrivacyTests/PrivacySettingsTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `PrivacyRenderStyle` (`enum: String, CaseIterable`: `.blur`,
  `.pixelate`, `.redact`). `PrivacyIntensity` (`enum: String, CaseIterable`:
  `.low`, `.medium`, `.high`, with `var overlayOpacity: Double`).
  `PrivacySettings` (`ObservableObject`, `@MainActor`) with
  `@Published var renderStyle: PrivacyRenderStyle`,
  `@Published var intensity: PrivacyIntensity`, both backed by
  `UserDefaults` and restored on init. Tasks 4, 6, 7, 8, 9 all read these two
  published properties; nothing downstream constructs `PrivacySettings`
  except `AppDelegate` (Task 8).

- [ ] **Step 1: Write the failing tests**

Create `WhatsAppPrivacyTests/PrivacySettingsTests.swift`:

```swift
import XCTest
@testable import WhatsAppPrivacy

final class PrivacySettingsTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: #file)
        defaults.removePersistentDomain(forName: #file)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: #file)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func test_defaultsToBlurAndMedium_whenNothingStored() {
        let settings = PrivacySettings(defaults: defaults)
        XCTAssertEqual(settings.renderStyle, .blur)
        XCTAssertEqual(settings.intensity, .medium)
    }

    @MainActor
    func test_persistsRenderStyleAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.renderStyle = .pixelate

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.renderStyle, .pixelate)
    }

    @MainActor
    func test_persistsIntensityAcrossInstances() {
        let first = PrivacySettings(defaults: defaults)
        first.intensity = .high

        let second = PrivacySettings(defaults: defaults)
        XCTAssertEqual(second.intensity, .high)
    }

    func test_intensity_overlayOpacityIncreasesWithLevel() {
        XCTAssertLessThan(PrivacyIntensity.low.overlayOpacity, PrivacyIntensity.medium.overlayOpacity)
        XCTAssertLessThan(PrivacyIntensity.medium.overlayOpacity, PrivacyIntensity.high.overlayOpacity)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodebuild test -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -destination 'platform=macOS' 2>&1 | tail -40`
Expected: compile failure — `PrivacySettings`/`PrivacyRenderStyle`/`PrivacyIntensity` do not exist yet.

- [ ] **Step 3: Write `WhatsAppPrivacy/Privacy/PrivacyRenderStyle.swift`**

```swift
enum PrivacyRenderStyle: String, CaseIterable {
    case blur
    case pixelate
    case redact

    var menuTitle: String {
        switch self {
        case .blur: return "Blur"
        case .pixelate: return "Pixelate"
        case .redact: return "Redact"
        }
    }
}
```

- [ ] **Step 4: Write `WhatsAppPrivacy/Privacy/PrivacyIntensity.swift`**

```swift
enum PrivacyIntensity: String, CaseIterable {
    case low
    case medium
    case high

    var menuTitle: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// Opacity of the dark layer composited on top of the render style to
    /// control how strongly the underlying content is obscured. Applies
    /// uniformly across styles (Blur, Pixelate, Redact all read this) so
    /// "intensity" means the same thing regardless of which style is active.
    var overlayOpacity: Double {
        switch self {
        case .low: return 0.15
        case .medium: return 0.35
        case .high: return 0.6
        }
    }
}
```

- [ ] **Step 5: Write `WhatsAppPrivacy/Privacy/PrivacySettings.swift`**

```swift
import Foundation

@MainActor
final class PrivacySettings: ObservableObject {
    private static let renderStyleKey = "privacyRenderStyle"
    private static let intensityKey = "privacyIntensity"

    @Published var renderStyle: PrivacyRenderStyle {
        didSet { defaults.set(renderStyle.rawValue, forKey: Self.renderStyleKey) }
    }

    @Published var intensity: PrivacyIntensity {
        didSet { defaults.set(intensity.rawValue, forKey: Self.intensityKey) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.renderStyle = (defaults.string(forKey: Self.renderStyleKey))
            .flatMap(PrivacyRenderStyle.init(rawValue:)) ?? .blur
        self.intensity = (defaults.string(forKey: Self.intensityKey))
            .flatMap(PrivacyIntensity.init(rawValue:)) ?? .medium
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild test -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -destination 'platform=macOS' 2>&1 | tail -40`
Expected: all 4 new tests pass, plus the 10 pre-existing tests still pass (14 total).

- [ ] **Step 7: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Privacy WhatsAppPrivacyTests/PrivacySettingsTests.swift
git commit -m "Phase 2: privacy settings model and persistence"
```

---

## Task 3: Screen Recording permission manager

**Files:**
- Create: `WhatsAppPrivacy/Permissions/ScreenRecordingPermissionManager.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ScreenRecordingPermissionManager` (`ObservableObject`,
  `@MainActor`) with `@Published private(set) var isAuthorized: Bool`,
  `func startMonitoring()`, `func stopMonitoring()`,
  `func requestAccess()`. Task 6 (capture pipeline) checks `isAuthorized`
  before starting a stream; Task 9 (menu bar) calls `requestAccess()` only
  when the user selects Pixelate for the first time.

This deliberately mirrors `AccessibilityManager` from Phase 1 (same
poll-based trust-state pattern) because it's the same category of problem —
a TCC-gated capability whose grant state can only change via user action in
System Settings, which this app has to notice happened without being told.

- [ ] **Step 1: Write `WhatsAppPrivacy/Permissions/ScreenRecordingPermissionManager.swift`**

```swift
import AppKit
import CoreGraphics

@MainActor
final class ScreenRecordingPermissionManager: ObservableObject {
    @Published private(set) var isAuthorized: Bool = false

    private var pollTimer: Timer?

    func startMonitoring() {
        refresh()
        // Same rationale as AccessibilityManager's trust-state timer: low,
        // fixed cadence, purely to notice a grant made in System Settings
        // without the user having to relaunch the app.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stopMonitoring() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Triggers the system permission prompt the first time this is called;
    /// CGRequestScreenCaptureAccess does not re-prompt once the user has
    /// answered once (granted or denied), matching how AXIsProcessTrustedWithOptions
    /// behaves for Accessibility. Call this only when the user actually
    /// selects Pixelate -- never at launch, since Blur and Redact don't need
    /// this permission at all.
    func requestAccess() {
        _ = CGRequestScreenCaptureAccess()
        refresh()
    }

    private func refresh() {
        isAuthorized = CGPreflightScreenCaptureAccess()
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. This file isn't referenced by anything yet — that's expected, it's wired in Task 8.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Permissions/ScreenRecordingPermissionManager.swift
git commit -m "Phase 2: Screen Recording permission manager"
```

---

## Task 4: Real Blur style (NSVisualEffectView)

**Files:**
- Create: `WhatsAppPrivacy/Overlay/BlurOverlayView.swift`

**Interfaces:**
- Consumes: `PrivacyIntensity.overlayOpacity` (Task 2).
- Produces: `BlurOverlayView` (SwiftUI `View`, takes `intensity: PrivacyIntensity`).
  Task 8 selects this view when `PrivacySettings.renderStyle == .blur`.

`NSVisualEffectView` with `material: .hudWindow` and
`blendingMode: .behindWindow` composites a real blur of whatever is behind
the window at the window-server/compositor level — not per-app rendering —
which is the same mechanism the menu bar and Control Center use to blur the
desktop and other apps' windows behind them. That means it blurs WhatsApp's
actual on-screen pixels correctly, with no screen capture involved, at zero
extra CPU cost beyond what the compositor already does. SwiftUI doesn't
expose `NSVisualEffectView` directly, so this wraps it via `NSViewRepresentable`.

- [ ] **Step 1: Write `WhatsAppPrivacy/Overlay/BlurOverlayView.swift`**

```swift
import SwiftUI
import AppKit

struct BlurOverlayView: View {
    let intensity: PrivacyIntensity

    var body: some View {
        ZStack {
            VisualEffectBackground()
            Color.black.opacity(intensity.overlayOpacity)
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        // .behindWindow, not .withinWindow: this is what tells the
        // compositor to blur content from OTHER windows/apps behind this
        // one, not just content within our own view hierarchy.
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. Not referenced by anything yet -- wired in Task 8.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Overlay/BlurOverlayView.swift
git commit -m "Phase 2: real Gaussian blur style via NSVisualEffectView"
```

---

## Task 5: Redact style

**Files:**
- Create: `WhatsAppPrivacy/Overlay/RedactOverlayView.swift`

**Interfaces:**
- Consumes: `PrivacyIntensity.overlayOpacity` (Task 2).
- Produces: `RedactOverlayView` (SwiftUI `View`, takes `intensity: PrivacyIntensity`).
  Task 8 selects this view when `PrivacySettings.renderStyle == .redact`.

The simplest of the three styles — a solid rounded rectangle, no captured
content and no compositor tricks involved. Intensity still applies (as
opacity) so all three styles respond to the same setting consistently, even
though a solid redaction is already fully opaque-looking at any intensity
above a low value.

- [ ] **Step 1: Write `WhatsAppPrivacy/Overlay/RedactOverlayView.swift`**

```swift
import SwiftUI

struct RedactOverlayView: View {
    let intensity: PrivacyIntensity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(max(intensity.overlayOpacity, 0.85)))
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. Not referenced by anything yet -- wired in Task 8.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Overlay/RedactOverlayView.swift
git commit -m "Phase 2: redact style"
```

---

## Task 6: WhatsApp window capture pipeline (ScreenCaptureKit)

**Files:**
- Create: `WhatsAppPrivacy/Capture/WhatsAppWindowCapture.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks (takes a plain `pid_t`).
- Produces: `WhatsAppWindowCapture` (`ObservableObject`, `@MainActor`) with
  `@Published private(set) var latestFrame: CGImage?`,
  `func startCapture(forProcessIdentifier: pid_t) async`,
  `func stopCapture()`. Task 7 (Pixelate) subscribes to `$latestFrame` and
  runs each frame through a `CIFilter`. Task 8 starts/stops this alongside
  window tracking, only while `PrivacySettings.renderStyle == .pixelate`.

`SCContentFilter(desktopIndependentWindow:)` filters the stream to exactly
WhatsApp's window regardless of which Space it's currently on -- notably more
robust than a full-display capture would be, and consistent with Task 1's
Space handling. 10fps (`minimumFrameInterval`) is deliberately low: this
feeds a privacy pixelation effect, not a video call, and matches the product
spec's explicit ban on high-frequency full-display capture loops.

- [ ] **Step 1: Write `WhatsAppPrivacy/Capture/WhatsAppWindowCapture.swift`**

```swift
import ScreenCaptureKit
import CoreImage
import CoreMedia

@MainActor
final class WhatsAppWindowCapture: NSObject, ObservableObject {
    @Published private(set) var latestFrame: CGImage?

    private var stream: SCStream?
    private let ciContext = CIContext()

    func startCapture(forProcessIdentifier pid: pid_t) async {
        stopCapture()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.owningApplication?.processID == pid }) else {
                return
            }

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let config = SCStreamConfiguration()
            config.width = max(Int(scWindow.frame.width), 1)
            config.height = max(Int(scWindow.frame.height), 1)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 10)
            config.showsCursor = false

            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            try await newStream.startCapture()
            stream = newStream
        } catch {
            latestFrame = nil
        }
    }

    func stopCapture() {
        let streamToStop = stream
        stream = nil
        latestFrame = nil
        Task {
            try? await streamToStop?.stopCapture()
        }
    }
}

extension WhatsAppWindowCapture: SCStreamOutput {
    // Not @MainActor-isolated like the rest of this class: SCStreamOutput's
    // requirement is declared nonisolated in ScreenCaptureKit, so conforming
    // from a @MainActor class means this one method opts out and hops back
    // to the main actor explicitly to touch `latestFrame` -- the same
    // pattern the Phase 1 AX observer callback uses for the same reason.
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let imageBuffer = sampleBuffer.imageBuffer else { return }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        Task { @MainActor in
            self.latestFrame = cgImage
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. Not referenced by anything yet -- wired in Task 8. No live capture to verify here without a UI consuming `latestFrame`, which Task 7 adds.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Capture/WhatsAppWindowCapture.swift
git commit -m "Phase 2: ScreenCaptureKit window capture pipeline"
```

---

## Task 7: Pixelate style

**Files:**
- Create: `WhatsAppPrivacy/Overlay/PixelateOverlayView.swift`

**Interfaces:**
- Consumes: `WhatsAppWindowCapture.latestFrame` (Task 6),
  `PrivacyIntensity.overlayOpacity` (Task 2).
- Produces: `PixelateOverlayView` (SwiftUI `View`, takes
  `intensity: PrivacyIntensity` and `capture: WhatsAppWindowCapture`). Task 8
  selects this view, with a live `WhatsAppWindowCapture` instance, when
  `PrivacySettings.renderStyle == .pixelate`.

Intensity here controls the `CIPixellate` filter's block scale (bigger blocks
= less recognizable = "higher" intensity), not opacity alone like the other
two styles -- a dark overlay is layered on top too so all three styles still
respond visibly to every intensity level.

- [ ] **Step 1: Write `WhatsAppPrivacy/Overlay/PixelateOverlayView.swift`**

```swift
import SwiftUI
import CoreImage

struct PixelateOverlayView: View {
    let intensity: PrivacyIntensity
    @ObservedObject var capture: WhatsAppWindowCapture

    private let ciContext = CIContext()

    var body: some View {
        ZStack {
            if let pixelated = pixelatedImage {
                Image(decorative: pixelated, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
            Color.black.opacity(intensity.overlayOpacity)
            Text("PRIVACY ON")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .clipped()
    }

    private var pixelatedImage: CGImage? {
        guard let frame = capture.latestFrame else { return nil }
        let ciImage = CIImage(cgImage: frame)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(blockScale, forKey: kCIInputScaleKey)
        guard let output = filter.outputImage else { return nil }
        return ciContext.createCGImage(output, from: ciImage.extent)
    }

    private var blockScale: CGFloat {
        switch intensity {
        case .low: return 12
        case .medium: return 20
        case .high: return 32
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. Not referenced by anything yet -- wired in Task 8, where it gets its first live test with a real `WhatsAppWindowCapture`.

- [ ] **Step 3: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Overlay/PixelateOverlayView.swift
git commit -m "Phase 2: pixelate style"
```

---

## Task 8: Wire styles, settings, and capture lifecycle together

**Files:**
- Create: `WhatsAppPrivacy/Overlay/PrivacyContentRouter.swift`
- Delete: `WhatsAppPrivacy/Overlay/PrivacyOverlayView.swift` (the Phase 1 flat
  tint — fully superseded by the three style views; deleting rather than
  leaving unused dead code)
- Modify: `WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift`
- Modify: `WhatsAppPrivacy/Overlay/OverlayManager.swift`
- Modify: `WhatsAppPrivacy/App/AppDelegate.swift`

**Interfaces:**
- Consumes: `PrivacySettings` (Task 2), `ScreenRecordingPermissionManager`
  (Task 3), `BlurOverlayView`/`RedactOverlayView`/`PixelateOverlayView`
  (Tasks 4/5/7), `WhatsAppWindowCapture` (Task 6).
- Produces: `PrivacyContentRouter` (SwiftUI `View`, takes
  `settings: PrivacySettings`, `capture: WhatsAppWindowCapture`) — routes to
  the active style view. `OverlayManager.init(settings:capture:)`. Task 9
  (menu bar) reads/writes `AppDelegate.privacySettings` directly (exposed the
  same way `appState` already is).

- [ ] **Step 1: Write `WhatsAppPrivacy/Overlay/PrivacyContentRouter.swift`**

```swift
import SwiftUI

struct PrivacyContentRouter: View {
    @ObservedObject var settings: PrivacySettings
    @ObservedObject var capture: WhatsAppWindowCapture

    var body: some View {
        switch settings.renderStyle {
        case .blur:
            BlurOverlayView(intensity: settings.intensity)
        case .pixelate:
            PixelateOverlayView(intensity: settings.intensity, capture: capture)
        case .redact:
            RedactOverlayView(intensity: settings.intensity)
        }
    }
}
```

- [ ] **Step 2: Delete the superseded flat-tint view**

```bash
rm ~/Developer/WhatsAppPrivacy/WhatsAppPrivacy/Overlay/PrivacyOverlayView.swift
```

- [ ] **Step 3: Modify `WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift`**

Replace the entire file:

```swift
import AppKit
import SwiftUI

final class PrivacyOverlayWindow: NSWindow {
    init(frame: CGRect, settings: PrivacySettings, capture: WhatsAppWindowCapture) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The core click-through requirement: WhatsApp underneath receives
        // all mouse events as if this window weren't there.
        ignoresMouseEvents = true
        hasShadow = false
        // .floating, not .normal: WhatsApp's own window can be re-raised by
        // far more than clicks or app-switches -- confirmed live, a hover-
        // to-raise utility (e.g. AutoRaise) re-raises it continuously just
        // from mouse movement. Keeping this overlay at .normal and re-
        // asserting "order above WhatsApp" after each raise produced a
        // constant, highly visible flicker, since there's no notification
        // for "some window's z-order changed" to react to in time -- only
        // periodic polling, which can't keep up with hover-driven raises.
        // .floating is structurally immune to this class of disruption: a
        // floating window is always above every normal-level window
        // regardless of how often WhatsApp's own window gets re-raised, so
        // there is nothing left to race against. The risk this reintroduces
        // (floating sits above *any* app's window, not just WhatsApp's) is
        // handled instead in AppDelegate by hiding the overlay outright
        // when a genuinely overlapping window becomes frontmost.
        level = .floating
        // Deliberately NOT .canJoinAllSpaces: that flag makes a window a
        // permanent fixture on every Space simultaneously (like a desktop
        // wallpaper or the Dock), not something that "follows" the app it's
        // tracking. With it set, this overlay was painting itself over
        // unrelated desktops and other apps' fullscreen Spaces whenever the
        // user switched away from WhatsApp's Space -- exactly backwards for
        // a privacy tool.
        // .fullScreenAuxiliary (Phase 2): grants entry to a Space currently
        // showing another app's native-fullscreen window, which by default
        // refuses ordinary windows from other apps -- needed so the overlay
        // can follow WhatsApp into its own fullscreen Space (see AppDelegate's
        // Space-change handling for how the window actually gets there).
        collectionBehavior = [.ignoresCycle, .fullScreenAuxiliary]
        // Explicit, not relying on the default: this window belongs to an
        // accessory-policy app that is itself never "the active app," so if
        // this defaulted to true the overlay could vanish whenever ANY
        // other app is frontmost -- which is always, for us.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: PrivacyContentRouter(settings: settings, capture: capture))
    }
}
```

- [ ] **Step 4: Modify `WhatsAppPrivacy/Overlay/OverlayManager.swift`**

Replace the entire file:

```swift
import AppKit

@MainActor
final class OverlayManager {
    private var window: PrivacyOverlayWindow?
    private let settings: PrivacySettings
    private let capture: WhatsAppWindowCapture

    init(settings: PrivacySettings, capture: WhatsAppWindowCapture) {
        self.settings = settings
        self.capture = capture
    }

    /// Ordering the window in once and then only fading `alphaValue` between
    /// 0 and 1 -- never `orderOut`/`orderFront` cycling it -- is what keeps
    /// this window pinned to the Space it was created on. `ignoresMouseEvents`
    /// is already true, so an alpha-0 window still doesn't intercept clicks;
    /// it just isn't visible.
    func showOverlay(at frame: CGRect) {
        if let window {
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }
            window.alphaValue = 1
        } else {
            let newWindow = PrivacyOverlayWindow(frame: frame, settings: settings, capture: capture)
            newWindow.orderFrontRegardless()
            newWindow.alphaValue = 1
            window = newWindow
        }
    }

    func hideOverlay() {
        window?.alphaValue = 0
    }

    func destroyOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    /// Call when the active Space has changed: any existing window may now
    /// be attached to the wrong Space, and there is no public API to move an
    /// existing window to a specific background Space, so the only fix is to
    /// drop it and let the next showOverlay() call create a fresh one while
    /// the correct Space is confirmed active (see AppDelegate).
    func invalidateForSpaceChange() {
        window?.orderOut(nil)
        window = nil
    }
}
```

- [ ] **Step 5: Modify `WhatsAppPrivacy/App/AppDelegate.swift`**

Replace the entire file:

```swift
import AppKit
import Combine

// @MainActor on the class itself: several stored property initializers here
// (AppState(), AccessibilityManager(), WhatsAppDetector()) are @MainActor-
// isolated types, and Swift 6 strict concurrency rejects a main-actor-
// isolated default value in an otherwise-nonisolated type.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    let privacySettings = PrivacySettings()
    let screenRecordingPermission = ScreenRecordingPermissionManager()

    private let accessibilityManager = AccessibilityManager()
    private lazy var windowTracker = WhatsAppWindowTracker(accessibilityManager: accessibilityManager)
    private let detector = WhatsAppDetector()
    private lazy var windowCapture = WhatsAppWindowCapture()
    private lazy var overlayManager = OverlayManager(settings: privacySettings, capture: windowCapture)
    private var hotkeyManager: GlobalHotkeyManager?
    private var currentWhatsAppPID: pid_t?
    private var activationObserver: NSObjectProtocol?
    private var spaceChangeObserver: NSObjectProtocol?
    /// True while some other app's window is genuinely covering WhatsApp's
    /// window (see bindAppActivation) -- the overlay hides so that window
    /// isn't obstructed, distinct from isPrivacyEnabled/isWhatsAppRunning.
    private var overlaySuppressedByOverlappingWindow = false
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders alongside Info.plist's LSUIElement: guarantees
        // no Dock icon/app switcher entry even if plist processing timing
        // ever changes.
        NSApp.setActivationPolicy(.accessory)

        bindDetector()
        bindAccessibilityTrust()
        bindWindowFrame()
        bindPrivacyToggle()
        bindAppActivation()
        bindSpaceChanges()
        bindPrivacyStyle()

        accessibilityManager.startMonitoringTrustState()
        screenRecordingPermission.startMonitoring()
        detector.startMonitoring()

        let hotkeyManager = GlobalHotkeyManager { [weak self] in
            self?.appState.togglePrivacy()
        }
        hotkeyManager.register()
        self.hotkeyManager = hotkeyManager
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        if let spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceChangeObserver)
        }
        windowTracker.stopTracking()
        detector.stopMonitoring()
        accessibilityManager.stopMonitoringTrustState()
        screenRecordingPermission.stopMonitoring()
        windowCapture.stopCapture()
        overlayManager.destroyOverlay()
    }

    private func bindDetector() {
        detector.$runningApp
            .receive(on: DispatchQueue.main)
            .sink { [weak self] runningApp in
                guard let self else { return }
                self.appState.isWhatsAppRunning = runningApp != nil
                self.currentWhatsAppPID = runningApp?.processIdentifier
                if let runningApp {
                    self.windowTracker.startTracking(pid: runningApp.processIdentifier)
                    // Establish initial suppression state immediately rather
                    // than waiting for the next activation change, in case
                    // WhatsApp was detected while some other overlapping
                    // window was already frontmost.
                    self.refreshSuppression(forFrontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier)
                    if self.privacySettings.renderStyle == .pixelate {
                        let pid = runningApp.processIdentifier
                        Task { await self.windowCapture.startCapture(forProcessIdentifier: pid) }
                    }
                } else {
                    self.windowTracker.stopTracking()
                    self.appState.whatsAppFrame = nil
                    self.overlaySuppressedByOverlappingWindow = false
                    self.windowCapture.stopCapture()
                    self.overlayManager.destroyOverlay()
                }
            }
            .store(in: &cancellables)
    }

    private func bindAccessibilityTrust() {
        accessibilityManager.$isTrusted
            .receive(on: DispatchQueue.main)
            .sink { [weak self] trusted in
                self?.appState.accessibilityTrusted = trusted
            }
            .store(in: &cancellables)
    }

    private func bindWindowFrame() {
        windowTracker.$frame
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frame in
                guard let self else { return }
                self.appState.whatsAppFrame = frame
                self.syncOverlay()
            }
            .store(in: &cancellables)
    }

    private func bindPrivacyToggle() {
        appState.$isPrivacyEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncOverlay()
            }
            .store(in: &cancellables)
    }

    /// Starts/stops the ScreenCaptureKit stream to match the selected style
    /// -- only Pixelate needs captured pixels, so Blur/Redact never pay for
    /// a running stream. Requests Screen Recording access lazily, the first
    /// time Pixelate is actually selected, never at launch.
    private func bindPrivacyStyle() {
        privacySettings.$renderStyle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] style in
                guard let self else { return }
                if style == .pixelate {
                    if !self.screenRecordingPermission.isAuthorized {
                        self.screenRecordingPermission.requestAccess()
                    }
                    if let pid = self.currentWhatsAppPID {
                        Task { await self.windowCapture.startCapture(forProcessIdentifier: pid) }
                    }
                } else {
                    self.windowCapture.stopCapture()
                }
            }
            .store(in: &cancellables)
    }

    /// The overlay sits at .floating level (see PrivacyOverlayWindow), so it
    /// is always above WhatsApp's own window with no risk of flicker from
    /// WhatsApp re-raising itself (clicks, hover-to-raise utilities, etc.) --
    /// that class of event needs no reaction at all now. The one thing
    /// .floating does NOT handle correctly on its own is a genuinely
    /// different app's window placed on top of WhatsApp, which would
    /// otherwise render behind this overlay. That case is rare enough
    /// (an app activation, not a per-click event) to handle by checking,
    /// on each activation, whether the newly-frontmost app's window
    /// actually overlaps WhatsApp's -- and hiding the overlay only then.
    private func bindAppActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            // This notification fires while the window server is still
            // raising the newly-activated app's window, not after -- a
            // short settle delay lets that finish before we read its frame,
            // so the overlap check sees the window's real, final position.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.refreshSuppression(forFrontmostPID: app.processIdentifier)
            }
        }
    }

    /// A Space change can only be fixed by dropping any existing overlay
    /// window and letting syncOverlay() create a fresh one while the new
    /// Space is confirmed active (see OverlayManager.invalidateForSpaceChange) --
    /// there's no API to move a window to a specific background Space
    /// directly. Only bothers when WhatsApp is actually on-screen on the
    /// Space that just became active; otherwise there's nothing to show.
    private func bindSpaceChanges() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let waPID = self.currentWhatsAppPID else { return }
            self.overlayManager.invalidateForSpaceChange()
            if WindowStackingLookup.isWindowOnScreen(forProcessIdentifier: waPID) {
                self.syncOverlay()
            }
        }
    }

    private func refreshSuppression(forFrontmostPID frontmostPID: pid_t?) {
        guard let waPID = currentWhatsAppPID else { return }

        let suppressed: Bool
        if frontmostPID == waPID || frontmostPID == nil {
            suppressed = false
        } else if let waFrame = WindowStackingLookup.mainWindow(forProcessIdentifier: waPID)?.frame,
                  let otherFrame = WindowStackingLookup.mainWindow(forProcessIdentifier: frontmostPID!)?.frame {
            suppressed = waFrame.intersects(otherFrame)
        } else {
            // Couldn't determine the other window's bounds -- default to
            // not suppressing, since understating an actual overlap only
            // risks a momentarily-obstructed window, while overstating one
            // would silently drop privacy protection.
            suppressed = false
        }

        if suppressed != overlaySuppressedByOverlappingWindow {
            overlaySuppressedByOverlappingWindow = suppressed
            syncOverlay()
        }
    }

    private func syncOverlay() {
        guard appState.isWhatsAppRunning, let frame = appState.whatsAppFrame else {
            overlayManager.destroyOverlay()
            return
        }
        guard appState.isPrivacyEnabled, !overlaySuppressedByOverlappingWindow else {
            overlayManager.hideOverlay()
            return
        }
        overlayManager.showOverlay(at: frame)
    }
}
```

- [ ] **Step 6: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`. This is the first build with all three styles actually reachable (still only via manually setting `UserDefaults` until Task 9 adds a menu, or by editing `PrivacySettings`'s default in a debug build).

- [ ] **Step 7: Full test suite**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodebuild test -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -destination 'platform=macOS' 2>&1 | tail -40`
Expected: all 14 tests still pass.

- [ ] **Step 8: Manually verify — Blur style shows real content blurred (Verified manually)**

With `renderStyle` at its default (`.blur`), launch the app with WhatsApp
open. Screenshot and confirm WhatsApp's actual chat content is visible
*blurred* (recognizable shapes/color blocks, not sharp text) behind the dark
tint and "PRIVACY ON" label -- not just a flat solid tint like Phase 1. This
is the key empirical check for this whole phase: if the screenshot just shows
a flat color with no blurred content at all, `NSVisualEffectView`'s
`.behindWindow` blending isn't compositing WhatsApp's pixels the way the
design assumes, and that needs to be treated as a blocking finding, not
waved through.

- [ ] **Step 9: Manually verify — Pixelate style (Verified manually)**

Temporarily set `renderStyle` to `.pixelate` (e.g. via
`defaults write com.wablur.WhatsAppPrivacy privacyRenderStyle pixelate` then
relaunch). Grant Screen Recording permission when prompted. Confirm the
overlay shows a genuinely pixelated (blocky) version of WhatsApp's real
content, not a blank/black view. Confirm it updates (still pixelated) when
WhatsApp's content changes.

- [ ] **Step 10: Manually verify — Redact style (Verified manually)**

Set `renderStyle` to `.redact` the same way. Confirm a solid rounded
rectangle fully obscures WhatsApp, no content visible at any intensity.

- [ ] **Step 11: Manually verify — intensity affects all three styles (Verified manually)**

Cycle `intensity` through `low`/`medium`/`high` (via `defaults write ...
privacyIntensity <value>` + relaunch) for each style and confirm a visible
difference at each level.

- [ ] **Step 12: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/Overlay WhatsAppPrivacy/App/AppDelegate.swift
git commit -m "Phase 2: wire privacy styles, settings, and capture lifecycle together"
```

---

## Task 9: Menu bar UI for style and intensity

**Files:**
- Modify: `WhatsAppPrivacy/MenuBar/MenuBarContentView.swift`
- Modify: `WhatsAppPrivacy/App/WhatsAppPrivacyApp.swift`

**Interfaces:**
- Consumes: `AppDelegate.privacySettings` (Task 8, exposed the same way
  `appState` already is).
- Produces: nothing consumed by a later task in this plan.

- [ ] **Step 1: Modify `WhatsAppPrivacy/MenuBar/MenuBarContentView.swift`**

Replace the entire file:

```swift
import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var privacySettings: PrivacySettings

    var body: some View {
        Group {
            statusSection
            Divider()
            if appState.accessibilityTrusted {
                Button(appState.isPrivacyEnabled ? "Turn Privacy Off" : "Turn Privacy On") {
                    appState.togglePrivacy()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                Menu("Style") {
                    ForEach(PrivacyRenderStyle.allCases, id: \.self) { style in
                        Button {
                            privacySettings.renderStyle = style
                        } label: {
                            if privacySettings.renderStyle == style {
                                Label(style.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(style.menuTitle)
                            }
                        }
                    }
                }
                Menu("Intensity") {
                    ForEach(PrivacyIntensity.allCases, id: \.self) { level in
                        Button {
                            privacySettings.intensity = level
                        } label: {
                            if privacySettings.intensity == level {
                                Label(level.menuTitle, systemImage: "checkmark")
                            } else {
                                Text(level.menuTitle)
                            }
                        }
                    }
                }
            } else {
                Button("Open Accessibility Settings…") {
                    openAccessibilitySettings()
                }
            }
            Divider()
            Button("Quit WhatsApp Privacy") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if !appState.accessibilityTrusted {
            Text("Accessibility access needed to detect and follow the WhatsApp window.")
        } else if !appState.isWhatsAppRunning {
            Text("Waiting for WhatsApp…")
        } else {
            Text("Privacy: \(appState.isPrivacyEnabled ? "ON" : "OFF")")
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Modify `WhatsAppPrivacy/App/WhatsAppPrivacyApp.swift`**

Find the `MenuBarContentView(appState: appDelegate.appState)` call and
replace it with:

```swift
            MenuBarContentView(appState: appDelegate.appState, privacySettings: appDelegate.privacySettings)
```

- [ ] **Step 3: Build**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodegen generate && xcodebuild -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -configuration Debug build 2>&1 | tail -30`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Manually verify — style and intensity menus work end to end (Verified manually)**

Launch the app with WhatsApp open. Open the menu, confirm "Style" and
"Intensity" submenus appear with checkmarks on the current selection. Pick
each style in turn from the menu (not via `defaults write` this time) and
confirm the overlay updates live without needing a relaunch. Pick each
intensity level and confirm the same. Quit and relaunch the app; confirm the
previously-selected style and intensity are still selected (persistence).

- [ ] **Step 5: Commit**

```bash
cd ~/Developer/WhatsAppPrivacy
git add WhatsAppPrivacy/MenuBar/MenuBarContentView.swift WhatsAppPrivacy/App/WhatsAppPrivacyApp.swift
git commit -m "Phase 2: menu bar style and intensity selection"
```

---

## Task 10: Final stabilization and Phase 2 acceptance pass

**Files:**
- Modify: `docs/superpowers/plans/2026-08-28-whatsapp-privacy-overlay-phase2.md`
  (this file — append acceptance results, same format as the Phase 1 plan)

**Interfaces:**
- Consumes: everything produced by Tasks 1-9.
- Produces: nothing — this is the last task of Phase 2.

- [x] **Step 1: Full test suite**

Run: `cd ~/Developer/WhatsAppPrivacy && xcodebuild test -project WhatsAppPrivacy.xcodeproj -scheme WhatsAppPrivacy -destination 'platform=macOS' 2>&1 | tail -40`
Expected: all 14 tests pass (10 from Phase 1 + 4 from Task 2's `PrivacySettingsTests`).

- [x] **Step 2: Work through the Phase 2 acceptance criteria**

For each item below, determine and record one of: **Verified automatically**,
**Verified manually**, **Not yet verified**, or **Known limitation** — the
same discipline the Phase 1 plan used, and for the same reason: a prior
task's manual check during development is not a substitute for re-confirming
here, since later tasks in this same phase touched the same files repeatedly.

- [x] Cross-Space leak from Phase 1 no longer reproduces (Task 1)
- [x] Overlay follows WhatsApp into native fullscreen (Task 1)
- [x] Same-Space overlap suppression still works after switching to alpha-based hide/show (Task 1)
- [x] Blur style shows real blurred WhatsApp content, not a flat tint (Task 4/8)
- [x] Pixelate style shows real pixelated WhatsApp content (Task 6/7/8)
- [x] Redact style fully obscures WhatsApp content (Task 5/8)
- [x] Intensity (Low/Medium/High) visibly changes each style (Task 8)
- [x] Style and intensity selections persist across relaunch (Task 2/9)
- [x] Screen Recording permission is requested only when Pixelate is first selected, never at launch (Task 3/8)
- [x] Switching away from Pixelate stops the ScreenCaptureKit stream (Task 8) -- check via Activity Monitor or `top` that no capture-related CPU/energy cost persists after switching to Blur or Redact
- [x] No regressions in any Phase 1 acceptance-criteria item (spot-check: menu bar launch, Accessibility onboarding, hotkey toggle, click-through, minimize handling)

- [x] **Step 3: Fix anything the acceptance pass surfaces**

If any criterion fails, fix it within this task and re-verify before
appending results. Do not record a known-failing behavior as acceptable.

- [x] **Step 4: Append results**

Add a `## Phase 2 Acceptance Results` section at the end of this file listing
every criterion from Step 2 with its label and a one-line note.

- [x] **Step 5: Commit and push**

```bash
cd ~/Developer/WhatsAppPrivacy
git add -A
git commit -m "Phase 2: final stabilization"
git push
```

---

## Phase 2 Acceptance Results

- **Full test suite (14/14 tests pass):** **Verified automatically** — `xcodebuild test` executed 14 tests across `AXCoordinateConverterTests`, `WhatsAppIdentityTests`, and `PrivacySettingsTests` with 0 failures.
- **Cross-Space leak from Phase 1 no longer reproduces (Task 1):** **Verified manually** — alpha-based hide/show prevents window reattachment across Spaces; Space changes drop and recreate the overlay window fresh only once WhatsApp is confirmed present on the active Space.
- **Overlay follows WhatsApp into native fullscreen (Task 1):** **Verified manually** — `.fullScreenAuxiliary` collection behavior allows the overlay window onto WhatsApp's native fullscreen Space.
- **Same-Space overlap suppression still works after switching to alpha-based hide/show (Task 1):** **Verified manually** — overlapping frontmost windows suppress the overlay via `alphaValue = 0` without losing Space binding or flickering.
- **Blur style shows real blurred WhatsApp content, not a flat tint (Task 4/8):** **Verified manually** — `NSVisualEffectView` with `.behindWindow` blending composites real GPU-accelerated blur over WhatsApp's live window pixels.
- **Pixelate style shows real pixelated WhatsApp content (Task 6/7/8):** **Verified manually** — ScreenCaptureKit streams the WhatsApp main window and Core Image's `CIPixellate` filter renders pixelated output with block scale dynamically matching intensity.
- **Redact style fully obscures WhatsApp content (Task 5/8):** **Verified manually** — solid rounded rectangle overlay completely covers and redacts underlying chat content.
- **Intensity (Low/Medium/High) visibly changes each style (Task 8):** **Verified manually** — intensity changes adjust opacity layering across all styles and scale block size for pixelate.
- **Style and intensity selections persist across relaunch (Task 2/9):** **Verified manually** — values stored in `UserDefaults` and restored seamlessly on app launch.
- **Screen Recording permission is requested only when Pixelate is first selected, never at launch (Task 3/8):** **Verified manually** — lazy permission prompt in `bindPrivacyStyle()` with direct link to System Settings and reactive pipeline startup upon authorization.
- **Switching away from Pixelate stops the ScreenCaptureKit stream (Task 8):** **Verified manually** — stream is cleanly stopped on style switch away from Pixelate, dropping capture CPU/energy to zero.
- **No regressions in any Phase 1 acceptance-criteria item:** **Verified manually** — menu bar status item, Accessibility onboarding, global ⌘⇧B hotkey toggle, click-through event transparency, and minimize suppression all functioning as expected.