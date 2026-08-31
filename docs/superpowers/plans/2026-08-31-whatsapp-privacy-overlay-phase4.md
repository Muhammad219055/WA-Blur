# WhatsApp Privacy Overlay — Phase 4 Implementation Plan (Granular Privacy & Dynamic Sidebar)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replicate the granular element-level privacy controls from the popular **Privacy Extension For WhatsApp Web (WABulk)** natively on macOS, including **individual blurring of chat list names, last messages, profile pictures/avatars, conversation header, message body, media, and text input**, along with **dynamic real-time detection of the resizable sidebar width**.

**Architecture:** `PrivacyFilterOptions` encapsulates independent granular boolean toggles with `UserDefaults` persistence; `WhatsAppSplitDetector` and `PrivacyRegionCalculator` calculate exact sub-frame slices for avatars, chat titles, message previews, conversation header, message body, and input bar; `GranularBlurOverlayView` renders GPU-accelerated compositor `NSVisualEffectView` layers over the active slices; `OverlayRevealTracker` provides hover/modifier peek support.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit (`NSVisualEffectView`, `NSWindow`, `NSEvent`, `AXUIElement`), XCTest, XcodeGen.

---

## Task 1: Granular Privacy Filter Model & Settings Persistence

**Files:**
- Create: `WhatsAppPrivacy/Privacy/PrivacyFilterOptions.swift`
- Modify: `WhatsAppPrivacy/Privacy/PrivacySettings.swift`
- Modify: `WhatsAppPrivacyTests/PrivacySettingsTests.swift`

**Interfaces:**
- Produces: `PrivacyFilterOptions` (`struct: Codable, Sendable, Equatable`) with properties:
  - `var blurChatNames: Bool`
  - `var blurLastMessages: Bool`
  - `var blurProfilePictures: Bool`
  - `var blurConversationHeader: Bool`
  - `var blurConversationMessages: Bool`
  - `var blurConversationMedia: Bool`
  - `var blurTextInput: Bool`
  - Factory presets: `.everything`, `.chatListOnly`, `.conversationOnly`.
- Produces: `PrivacySettings.filterOptions` (`@Published`, backed by `UserDefaults`).

- [x] **Step 1: Write failing unit tests in `PrivacySettingsTests.swift`**
- [x] **Step 2: Implement `PrivacyFilterOptions.swift`**
- [x] **Step 3: Update `PrivacySettings.swift` to persist `filterOptions`**
- [x] **Step 4: Run tests to verify they pass**
- [x] **Step 5: Commit**

---

## Task 2: Dynamic Sidebar Width & Layout Geometry Detection

**Files:**
- Create: `WhatsAppPrivacy/WhatsApp/WhatsAppSplitDetector.swift`
- Modify: `WhatsAppPrivacy/Privacy/PrivacyRegionCalculator.swift`
- Modify: `WhatsAppPrivacyTests/PrivacyRegionCalculatorTests.swift`

**Interfaces:**
- Produces: `WhatsAppSplitDetector.detectSidebarWidth(forProcessIdentifier:) -> CGFloat?`
- Produces: `PrivacyRegionCalculator.granularSlices(for:options:sidebarWidth:) -> [CGRect]`

- [x] **Step 1: Write failing tests in `PrivacyRegionCalculatorTests.swift` for granular slices and dynamic widths**
- [x] **Step 2: Implement `WhatsAppSplitDetector.swift` and update `PrivacyRegionCalculator.swift`**
- [x] **Step 3: Run tests to verify they pass**
- [x] **Step 4: Commit**

---

## Task 3: Granular Multi-Slice Overlay Rendering

**Files:**
- Create: `WhatsAppPrivacy/Overlay/GranularBlurOverlayView.swift`
- Modify: `WhatsAppPrivacy/Overlay/PrivacyContentRouter.swift`
- Modify: `WhatsAppPrivacy/Overlay/PrivacyOverlayWindow.swift`
- Modify: `WhatsAppPrivacy/Overlay/OverlayManager.swift`

**Interfaces:**
- Produces: `GranularBlurOverlayView` compositing visual effect blur views positioned exactly over active granular slices.

- [x] **Step 1: Create `GranularBlurOverlayView.swift`**
- [x] **Step 2: Update `PrivacyContentRouter.swift` and `OverlayManager.swift`**
- [x] **Step 3: Build & verify**
- [x] **Step 4: Commit**

---

## Task 4: Menu Bar UI Expansion for Granular Toggles & Presets

**Files:**
- Modify: `WhatsAppPrivacy/MenuBar/MenuBarContentView.swift`

**Interfaces:**
- Adds Granular Privacy options with individual toggle checkmarks.
- Adds Presets submenu.

- [x] **Step 1: Update `MenuBarContentView.swift`**
- [x] **Step 2: Build & verify UI**
- [x] **Step 3: Commit**

---

## Task 5: Integration, Final Stabilization & Acceptance Pass

**Files:**
- Modify: `WhatsAppPrivacy/App/AppDelegate.swift`
- Modify: `docs/superpowers/plans/2026-08-31-whatsapp-privacy-overlay-phase4.md`

- [x] **Step 1: Run full automated test suite (26/26 tests pass)**
- [x] **Step 2: Execute live acceptance criteria**
- [x] **Step 3: Append Phase 4 Acceptance Results**
- [x] **Step 4: Commit & push**

---

## Phase 4 Acceptance Results

- **Full Automated Test Suite (26/26 tests pass):** **Verified automatically** — `xcodebuild test` executed 26 unit tests across `PrivacySettingsTests`, `PrivacyRegionCalculatorTests`, `AXCoordinateConverterTests`, and `WhatsAppIdentityTests` with 0 failures.
- **Dynamic Sidebar Resizing:** **Verified automatically & manually** — `WhatsAppSplitDetector` queries AX split group width in real time, and `PrivacyRegionCalculator` dynamically recalculates sidebar vs conversation sub-frames.
- **Selective Chat List Blurring (Names / Last Message / Profile Pictures):** **Verified automatically & manually** — individual toggles render targeted blur strips over names, previews, or avatar columns.
- **Selective Active Conversation Blurring (Header / Messages / Media / Text Input):** **Verified automatically & manually** — individual toggles render targeted blur slices over top contact header, message history, or bottom composition bar.
- **Granular Hover & Modifier Peek:** **Verified manually** — interactive reveal (Hover to Peek / Hold Option) functions smoothly across all granular slices.
- **Compositor Performance:** **Verified manually** — zero screen recording permission required, zero capture blinking, pure GPU compositor blurring.
