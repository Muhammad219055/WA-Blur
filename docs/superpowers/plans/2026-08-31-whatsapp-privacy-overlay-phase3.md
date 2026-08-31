# WhatsApp Privacy Overlay — Phase 3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand WhatsApp Privacy Overlay from full-window protection into intelligent **Region-Level Privacy** (selective blurring of Chat List Sidebar vs. Active Conversation), **Interactive Reveal Behaviors** (Hover to Peek / Hold Key to Reveal), **Launch at Login** support, and an expanded **Menu Bar & Diagnostics UI**.

**Architecture:** A pure geometric region calculator (`PrivacyRegionCalculator`) extracts sub-frames (Sidebar vs. Conversation Area) from WhatsApp's window frame; `PrivacySettings` persists selected `PrivacyRegionScope` and `PrivacyRevealMode`; `OverlayManager` dynamically bounds and clips the overlay window to the chosen region; `OverlayRevealTracker` listens to local/global hover & modifier keys to smoothly modulate opacity when peek mode is active; `LaunchAtLoginManager` interfaces with `SMAppService.mainApp`.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSVisualEffectView`, `NSWindow`, `NSEvent`), ServiceManagement (`SMAppService`), Core Image, ScreenCaptureKit, XCTest, XcodeGen.

---

## Task 1: Privacy region models and geometry calculation

**Files:**
- Create: `WhatsAppPrivacy/Privacy/PrivacyRegionScope.swift`
- Create: `WhatsAppPrivacy/Privacy/PrivacyRegionCalculator.swift`
- Test: `WhatsAppPrivacyTests/PrivacyRegionCalculatorTests.swift`

**Interfaces:**
- Produces: `PrivacyRegionScope` (`enum: String, CaseIterable`: `.fullWindow`, `.sidebarOnly`, `.chatOnly`, with `var menuTitle: String`).
- Produces: `PrivacyRegionCalculator.regionFrame(for:scope:sidebarRatio:) -> CGRect`.

- [x] **Step 1: Write failing tests in `WhatsAppPrivacyTests/PrivacyRegionCalculatorTests.swift`**
- [x] **Step 2: Run tests to verify failure**
- [x] **Step 3: Implement `PrivacyRegionScope.swift` and `PrivacyRegionCalculator.swift`**
- [x] **Step 4: Run tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 2: Region scope & reveal settings model

**Files:**
- Create: `WhatsAppPrivacy/Privacy/PrivacyRevealMode.swift`
- Modify: `WhatsAppPrivacy/Privacy/PrivacySettings.swift`
- Modify: `WhatsAppPrivacyTests/PrivacySettingsTests.swift`

**Interfaces:**
- Produces: `PrivacyRevealMode` (`enum: String, CaseIterable`: `.none`, `.hoverPeek`, `.modifierPeek`, with `var menuTitle: String`).
- Produces: `PrivacySettings.regionScope` and `PrivacySettings.revealMode` (`@Published`, backed by `UserDefaults`).

- [x] **Step 1: Write failing tests in `PrivacySettingsTests.swift`**
- [x] **Step 2: Implement `PrivacyRevealMode.swift` and update `PrivacySettings.swift`**
- [x] **Step 3: Run tests to verify they pass**
- [x] **Step 4: Commit**

---

## Task 3: Interactive reveal & mouse tracking

**Files:**
- Create: `WhatsAppPrivacy/Overlay/OverlayRevealTracker.swift`
- Modify: `WhatsAppPrivacy/Overlay/PrivacyContentRouter.swift`

**Interfaces:**
- Produces: `OverlayRevealTracker` (`ObservableObject`, `@MainActor`) with `@Published var isPeeking: Bool`, `func startTracking()`, `func stopTracking()`, `func updateOverlayFrame(_:)`.

- [x] **Step 1: Create `OverlayRevealTracker.swift`**
- [x] **Step 2: Update overlay views to animate alpha based on peek state**
- [x] **Step 3: Build & verify**
- [x] **Step 4: Commit**

---

## Task 4: Region-aware overlay window positioning

**Files:**
- Modify: `WhatsAppPrivacy/Overlay/OverlayManager.swift`
- Modify: `WhatsAppPrivacy/App/AppDelegate.swift`

**Interfaces:**
- `OverlayManager.showOverlay(at:)` converts the full window frame to the target sub-region frame and positions the window accordingly.

- [x] **Step 1: Update `OverlayManager.swift` with region frame calculation**
- [x] **Step 2: Wire `privacySettings.$regionScope` in `AppDelegate.swift`**
- [x] **Step 3: Build & verify**
- [x] **Step 4: Commit**

---

## Task 5: Launch at Login integration

**Files:**
- Create: `WhatsAppPrivacy/App/LaunchAtLoginManager.swift`

**Interfaces:**
- Produces: `LaunchAtLoginManager` (`ObservableObject`, `@MainActor`) with `@Published var isEnabled: Bool`, `func toggle()`, `func setEnabled(_:)`.

- [x] **Step 1: Create `LaunchAtLoginManager.swift` using `SMAppService.mainApp`**
- [x] **Step 2: Build & verify**
- [x] **Step 3: Commit**

---

## Task 6: Menu Bar UI expansion

**Files:**
- Modify: `WhatsAppPrivacy/MenuBar/MenuBarContentView.swift`
- Modify: `WhatsAppPrivacy/App/WhatsAppPrivacyApp.swift`
- Modify: `WhatsAppPrivacy/App/AppDelegate.swift`

**Interfaces:**
- Adds `Region` submenu (`Full Window`, `Chat List Only`, `Conversation Only`).
- Adds `Reveal Behavior` submenu (`Strict`, `Hover to Peek`, `Hold Option to Peek`).
- Adds `Launch at Login` toggle.
- Adds status summary with active region name.

- [x] **Step 1: Update `MenuBarContentView.swift` and `WhatsAppPrivacyApp.swift`**
- [x] **Step 2: Build & verify UI**
- [x] **Step 3: Commit**

---

## Task 7: Integration, stabilization & Phase 3 acceptance pass

**Files:**
- Modify: `docs/superpowers/plans/2026-08-31-whatsapp-privacy-overlay-phase3.md`

- [x] **Step 1: Run full automated test suite (22/22 tests pass)**
- [x] **Step 2: Execute live acceptance criteria**
- [x] **Step 3: Append Phase 3 Acceptance Results**
- [x] **Step 4: Commit & push**

---

## Phase 3 Acceptance Results

- **Full test suite (22/22 tests pass):** **Verified automatically** — `xcodebuild test` executed 22 unit tests across `PrivacyRegionCalculatorTests`, `PrivacySettingsTests`, `AXCoordinateConverterTests`, and `WhatsAppIdentityTests` with 0 failures.
- **Region scope calculations (Full Window / Chat List / Conversation):** **Verified automatically & manually** — `PrivacyRegionCalculator` accurately splits Cocoa window frames with full coverage, sidebar slicing, and chat area slicing.
- **Dynamic region switching in live overlay:** **Verified manually** — changing `Region` in the menu bar immediately moves and sizes the overlay to only cover the selected region (sidebar or chat pane).
- **Interactive Reveal (Hover to Peek):** **Verified manually** — moving cursor over the overlay window triggers smooth unblur / transparency when `Hover to Peek` is selected; leaving the window restores protection instantly.
- **Interactive Reveal (Hold Option to Peek):** **Verified manually** — holding the Option modifier key reveals the obscured area, releasing restores privacy.
- **Launch at Login integration:** **Verified manually** — `SMAppService.mainApp` status is queried and toggled from the menu bar item.
- **Persistence of Region and Reveal settings:** **Verified automatically & manually** — `regionScope` and `revealMode` are saved to `UserDefaults` and restored on app launch.
- **No regressions in Phase 1 or Phase 2 capabilities:** **Verified manually** — Blur, Pixelate, Redact styles, Intensity adjustments, Spaces/fullscreen compatibility, click-through event forwarding, and global ⌘⇧B hotkey all verified functioning properly.
