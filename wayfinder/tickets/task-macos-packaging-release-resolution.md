---
type: task-resolution
ticket: issue-9
status: resolved
date: 2026-09-04
url: https://github.com/RafaelScharf/SwarmDeck/issues/9
branch: feat/issue-9-packaging-release
---

# Resolution: Task - macOS App Packaging, Entitlements & Release Setup

## Question
How do we configure the macOS application target, entitlements, and build pipeline to produce a standalone signed/notarized `.app` bundle that can launch arbitrary CLI tools and send system notifications?

## Findings & Implementation

1. **Bundle & Plist Configuration (`Resources/Info.plist`):**
   - Configured standard Apple `Info.plist` with:
     - `CFBundleIdentifier`: `com.rafaelscharf.SwarmDeck`
     - `CFBundleName` / `CFBundleDisplayName`: `SwarmDeck`
     - `CFBundleExecutable`: `SwarmDeck`
     - `CFBundlePackageType`: `APPL`
     - `LSMinimumSystemVersion`: `14.0` (macOS Sonoma+)
     - `NSHighResolutionCapable`: `true` (Retina display support)
     - `LSApplicationCategoryType`: `public.app-category.developer-tools`
     - `NSUserNotificationAlertStyle`: `alert`
     - `CFBundleIconFile`: `AppIcon`
     - `NSSupportsAutomaticGraphicsSwitching`: `true`
     - `NSRequiresAquaSystemAppearance`: `false` (Native dark mode support)

2. **Entitlements & Execution Privileges (`Resources/SwarmDeck.entitlements`):**
   - Configured security profile for terminal emulation and developer agent orchestration:
     - `com.apple.security.app-sandbox: false` — Explicitly disabling App Sandbox is required for terminal emulators and agent supervisors because `forkpty()` must spawn user-installed CLI runtimes (Node.js, Python, Claude Code, Aider, Antigravity) from the user's `$PATH` and access developer workspaces without filesystem sandbox constraints.
     - Hardened runtime allowances:
       - `com.apple.security.cs.allow-jit: true`
       - `com.apple.security.cs.allow-unsigned-executable-memory: true`
       - `com.apple.security.cs.disable-library-validation: true`
       - `com.apple.security.get-task-allow: true`

3. **High-Resolution Vector App Icon Assets (`scripts/generate_icon.swift` & `Resources/AppIcon.icns`):**
   - Programmatically implemented vector icon rendering engine using AppKit (`NSImage`, `NSBezierPath`, `NSGradient`):
     - Renders macOS squircle canvas with drop shadow, dark slate gradient, subtle inner border, and macOS window control dots (red, yellow, green).
     - Renders neon cyan terminal prompt `>_`.
     - Renders 4 radiant glowing agent constellation nodes (representing Claude Code, Aider, Antigravity, Shell).
     - Generates 10 icon resolutions (16x16 up to 1024x1024 @2x).
     - Compiles into 310KB multi-resolution `Resources/AppIcon.icns` via `iconutil`.

4. **Standalone Packaging & Distribution Pipeline (`scripts/package_app.sh` & `Makefile`):**
   - Automated packaging script:
     - Compiles production binary via `swift build -c release --product SwarmDeck`.
     - Assembles bundle directory structure (`Contents/MacOS`, `Contents/Resources`).
     - Bundles `GhosttyKit_GhosttyTerminal.bundle` containing `terminfo` databases and shell integrations, synthesizing an `Info.plist` for valid code signing.
     - Preserves `SwarmDeck.dSYM` for crash diagnostics and symbolication.
     - Signs nested resource bundles and the main application with entitlements via `codesign`.
     - Verifies bundle integrity (`codesign --verify --deep --strict --verbose=2` and `plutil -lint`).
     - Supports building distributable ZIP (`--zip`) and DMG (`--dmg`) disk images.
   - Added root `Makefile` exposing standard targets: `make app`, `make zip`, `make dmg`, `make run`, `make test`, `make clean`.

## Test Validation
- Created comprehensive 41-point automated verification suite in `temp/prototypes/test_packaging_release.swift`.
- Tested:
  1. Plist XML integrity and verification of all required metadata keys (`com.rafaelscharf.SwarmDeck`, 14.0+, Retina, alert notifications).
  2. Hardened runtime entitlements validation (App Sandbox disabled, JIT, unsigned executable memory).
  3. AppIcon ICNS validity (>100KB, `'icns'` magic bytes, icon generator script availability).
  4. Packaging script execution, folder hierarchy, executable binary permissions, and Ghostty terminfo bundling.
  5. Strict code signing verification and designated requirement check.
  6. Binary Mach-O 64-bit architecture inspection and verification of generated `.zip` and `.dmg` distributables.
- All 41 tests passed with 100% success rate.
