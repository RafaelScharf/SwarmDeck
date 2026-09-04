---
type: research-resolution
ticket: libghostty-swift-integration
status: resolved
date: 2026-09-03
---

# libghostty Swift Integration: Technical Architecture & Implementation Guide

## Executive Summary
Ghostty achieves industry-leading terminal performance by coupling a cross-platform core written in **Zig** with native UI frontends. On macOS, Ghostty itself—as well as specialized AI-agent multiplexers like **cmux** (by manaflow-ai)—bridges the Zig core into native **Swift / AppKit / SwiftUI** via a C-ABI layer packaged into an Apple **`GhosttyKit.xcframework`**.

The rendering pipeline utilizes hardware-accelerated **Metal** directly on macOS: when a native `NSView` is passed to `ghostty_surface_new`, `libghostty` attaches a `CAMetalLayer` and spins up its own internal rendering thread driven by PTY output events. SwiftUI applications embed this surface using `NSViewRepresentable`.

---

## 1. Bridging Architecture: Zig/C to Swift

Ghostty uses a shared-core architecture detailed by Mitchell Hashimoto:
1. **Core in Zig (`libghostty`):** Handles VT sequence parsing, grid buffer, font shaping/rasterization, PTY spawning, and raw Metal GPU rendering.
2. **C ABI Export (`include/ghostty.h`):** The Zig core exports functions using `export fn ... callconv(.C)`. `ghostty.h` provides the C declarations and opaque handle types.
3. **Packaging (`GhosttyKit.xcframework`):** Zig's build system (`build.zig`) builds static universal libraries (`libghostty.a` for `arm64-apple-macos` and `x86_64-apple-macos`), bundles `include/ghostty.h`, and adds a Clang `module.modulemap`:
   ```modulemap
   module GhosttyKit {
       header "ghostty.h"
       export *
   }
   ```
4. **Swift Import:** In Swift, adding `GhosttyKit.xcframework` to the Xcode project or SPM `Package.swift` allows direct invocation:
   ```swift
   import GhosttyKit
   ```

### Linking Requirements (macOS System Frameworks)
When linking `GhosttyKit` (or `libghostty.a`), the host Swift application must link the following macOS system frameworks:
- `Metal.framework`
- `MetalKit.framework`
- `QuartzCore.framework` (for `CAMetalLayer` and `IOSurface`)
- `AppKit.framework`
- `CoreText.framework`
- `Carbon.framework`
- `IOKit.framework`
- `SystemConfiguration.framework`

---

## 2. Exposed C API Surface (`ghostty.h`)

The core C API is handle-based and opaque to preserve ABI stability:

### 2.1 Opaque Types
- `ghostty_app_t`: Handle to the global Ghostty application instance.
- `ghostty_surface_t`: Handle to an individual terminal surface (a viewport/window/pane).
- `ghostty_config_t`: Handle to a configuration object.

### 2.2 Configuration Lifecycle
- `ghostty_config_new() -> ghostty_config_t`: Creates a default config object.
- `ghostty_config_load_default_files(ghostty_config_t)`: Loads user configuration (e.g. from `~/.config/ghostty/config`).
- `ghostty_config_free(ghostty_config_t)`: Frees the configuration object.

### 2.3 Application Runtime Lifecycle
```c
typedef struct ghostty_runtime_config_s {
    void *userdata;
    void (*wakeup_cb)(void *userdata);
    void (*set_title_cb)(void *userdata, const char *title);
    void (*read_clipboard_cb)(void *userdata, ...);
    void (*write_clipboard_cb)(void *userdata, const char *text, size_t len);
    void (*close_surface_cb)(void *userdata, ghostty_surface_t surface);
    void (*action_cb)(void *userdata, ghostty_action_t action);
} ghostty_runtime_config_s;

ghostty_app_t ghostty_app_new(const ghostty_runtime_config_s *runtime_config, ghostty_config_t config);
void ghostty_app_free(ghostty_app_t app);
```
> [!IMPORTANT]
> **Main Thread Requirement:** `ghostty_app_new` **must** be called on the macOS main thread. Internally on macOS, it invokes AppKit and Text Input Source (TIS) APIs which raise exceptions if initialized on a background thread.

### 2.4 Surface Lifecycle & Geometry
```c
typedef struct ghostty_surface_config_s {
    void *userdata;               // Context pointer (e.g., Swift NSView instance)
    void *nsview;                 // Unmanaged pointer to the NSView
    double scale_factor;          // Window/Screen backingScaleFactor (e.g., 2.0 for Retina)
    const char *working_directory;// Optional initial CWD
    const char *command;          // Optional custom command (default: user shell)
} ghostty_surface_config_s;

ghostty_surface_t ghostty_surface_new(ghostty_app_t app, const ghostty_surface_config_s *config);
void ghostty_surface_free(ghostty_surface_t surface);

// Geometry updates
void ghostty_surface_set_size(ghostty_surface_t surface, uint32_t width, uint32_t height);
void ghostty_surface_set_content_scale(ghostty_surface_t surface, double x_scale, double y_scale);
void ghostty_surface_resize(ghostty_surface_t surface, int rows, int cols);
```

### 2.5 Input Forwarding
- `ghostty_surface_key(ghostty_surface_t surface, ...)`: Sends key events (keycodes, modifiers, state).
- `ghostty_surface_text(ghostty_surface_t surface, const char *text, size_t len)`: Sends committed UTF-8 text (pasting, IME output).
- `ghostty_surface_mouse_button(...)` / `mouse_motion`: Forwards mouse clicks, hover, and scroll wheel deltas.

### 2.6 Introspection & Process Management
- `pid_t ghostty_surface_child_pid(ghostty_surface_t surface)`: Returns the PID of the spawned shell / process.
- `const char *ghostty_surface_tty(ghostty_surface_t surface)`: Returns the slave PTY device path (e.g. `/dev/ttys003`).

---

## 3. Rendering Mechanics: Critical Architecture Insights

1. **Self-Contained Metal Rendering Thread:**
   When `ghostty_surface_new` receives an `NSView`, Ghostty internally configures a `CAMetalLayer` and manages an internal rendering thread.
2. **Anti-Pattern Warning (Do Not Draw Manually):**
   Host applications **must NOT** create an app-level display link (`CADisplayLink`) or call a manual draw loop. Ghostty internally schedules rendering only when dirty terminal state or PTY wakeups occur. Implementing a manual draw loop introduces thread contention and severe typing latency.
3. **Host Responsibility:**
   The host's only rendering responsibility is providing the view, updating the framebuffer size (`ghostty_surface_set_size`) and DPI scale (`ghostty_surface_set_content_scale`) when layout changes, and passing user input.

---

## 4. Native SwiftUI Integration on macOS

### Step 1: Build or Acquire `GhosttyKit.xcframework`
In the `ghostty` repository:
```bash
zig build -Demit-xcframework=true -Doptimize=ReleaseFast
```
Add `GhosttyKit.xcframework` to SwarmDeck's SPM package:
```swift
// Package.swift
.binaryTarget(
    name: "GhosttyKit",
    path: "Frameworks/GhosttyKit.xcframework"
)
```

### Step 2: Global Engine Manager (`GhosttyManager.swift`)
```swift
import Foundation
import GhosttyKit

@MainActor
final class GhosttyManager {
    static let shared = GhosttyManager()
    private(set) var appHandle: ghostty_app_t?
    
    private init() {
        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.wakeup_cb = { userdata in
            // Trigger host event loop wakeup if needed
        }
        runtimeConfig.set_title_cb = { userdata, titlePtr in
            guard let titlePtr = titlePtr else { return }
            let title = String(cString: titlePtr)
            // Post notification or route title update to active session
        }
        
        let config = ghostty_config_new()
        ghostty_config_load_default_files(config)
        
        self.appHandle = ghostty_app_new(&runtimeConfig, config)
        ghostty_config_free(config)
    }
    
    deinit {
        if let app = appHandle {
            ghostty_app_free(app)
        }
    }
}
```

### Step 3: AppKit Surface View (`GhosttySurfaceNSView.swift`)
```swift
import AppKit
import GhosttyKit

final class GhosttySurfaceNSView: NSView, NSTextInputClient {
    private var surface: ghostty_surface_t?
    private let workingDirectory: String?
    private let initialCommand: String?
    
    init(workingDirectory: String? = nil, initialCommand: String? = nil) {
        self.workingDirectory = workingDirectory
        self.initialCommand = initialCommand
        super.init(frame: .zero)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) { fatalError() }
    
    override var acceptsFirstResponder: Bool { true }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window = window, surface == nil else { return }
        initSurface(scale: window.backingScaleFactor)
    }
    
    private func initSurface(scale: CGFloat) {
        guard let app = GhosttyManager.shared.appHandle else { return }
        
        var config = ghostty_surface_config_s()
        config.userdata = Unmanaged.passUnretained(self).toOpaque()
        config.nsview = Unmanaged.passUnretained(self).toOpaque()
        config.scale_factor = Double(scale)
        
        if let cwd = workingDirectory {
            config.working_directory = (cwd as NSString).utf8String
        }
        if let cmd = initialCommand {
            config.command = (cmd as NSString).utf8String
        }
        
        self.surface = ghostty_surface_new(app, &config)
        updateGeometry()
    }
    
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateGeometry()
    }
    
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateGeometry()
    }
    
    private func updateGeometry() {
        guard let surface = surface, let window = window else { return }
        let scale = window.backingScaleFactor
        let pixelWidth = UInt32(bounds.width * scale)
        let pixelHeight = UInt32(bounds.height * scale)
        
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))
        ghostty_surface_set_size(surface, pixelWidth, pixelHeight)
    }
    
    // Keyboard & Input Forwarding
    override func keyDown(with event: NSEvent) {
        self.interpretKeyEvents([event])
    }
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = string as? String, let surface = surface else { return }
        text.withCString { ptr in
            ghostty_surface_text(surface, ptr, strlen(ptr))
        }
    }
    
    // Minimal NSTextInputClient stubs
    func hasMarkedText() -> Bool { false }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {}
    func unmarkText() {}
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
    
    deinit {
        if let surface = surface {
            ghostty_surface_free(surface)
        }
    }
}
```

### Step 4: SwiftUI Bridge (`GhosttyTerminalView.swift`)
```swift
import SwiftUI

struct GhosttyTerminalView: NSViewRepresentable {
    let workingDirectory: String?
    let command: String?
    
    func makeNSView(context: Context) -> GhosttySurfaceNSView {
        return GhosttySurfaceNSView(workingDirectory: workingDirectory, initialCommand: command)
    }
    
    func updateNSView(_ nsView: GhosttySurfaceNSView, context: Context) {
        // Layout and focus updates
    }
}
```

### Step 5: SwarmDeck Multiplexing Strategy
To ensure AI coding agent sessions continue running in the background when not focused:
- Maintain an active `ghostty_surface_t` per `AgentSession` in memory.
- When switching sessions in the sidebar (`NavigationSplitView`), switch the visible view or attach/detach surfaces without calling `ghostty_surface_free`.
- Use `ghostty_surface_child_pid` and `ghostty_surface_tty` to attach background output monitoring and regex state detection for sidebar notifications.

---

## Conclusion
Integrating `libghostty` into SwarmDeck is clean and fully viable:
1. `GhosttyKit.xcframework` bridges the Zig core into Swift via Clang module mapping.
2. Initializing `ghostty_app_t` on the main thread provides global runtime hooks.
3. Passing an layer-backed `NSView` to `ghostty_surface_new` yields GPU-accelerated Metal terminal rendering.
4. Wrapping in `NSViewRepresentable` allows seamless SwiftUI composition with zero WebView overhead.
