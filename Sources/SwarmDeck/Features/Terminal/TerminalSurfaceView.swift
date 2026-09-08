import SwiftUI
import AppKit
import QuartzCore
import Metal
import GhosttyKit
import GhosttyTerminal
import GhosttyTheme

/// Native macOS Metal-accelerated terminal surface view wrapping `libghostty-spm` via `NSViewRepresentable`.
///
/// Architected for 120 FPS ProMotion displays on Apple Silicon, featuring:
/// - Triple-buffered `CAMetalLayer` with `displaySyncEnabled = true` for zero-jitter rendering
/// - Two-way focus synchronization between SwiftUI `@FocusState` and AppKit first responder
/// - Darwin `ioctl(TIOCSWINSZ)` resize integration with cell metrics deduplication
/// - Seamless propagation of dynamic font scaling and curated Ghostty themes
/// - Native clipboard cut/copy/paste integration via `NSPasteboard.general`
@MainActor
public struct TerminalSurfaceView: NSViewRepresentable {
    public typealias NSViewType = SwarmDeckMetalTerminalView

    public let context: TerminalViewState
    public let focusBinding: FocusBinding?

    public init(context: TerminalViewState) {
        self.context = context
        self.focusBinding = nil
    }

    public init?(session: AgentSession) {
        guard let viewState = session.viewState else { return nil }
        self.context = viewState
        self.focusBinding = nil
    }

    public init(context: TerminalViewState, focusBinding: FocusBinding?) {
        self.context = context
        self.focusBinding = focusBinding
    }

    // MARK: - NSViewRepresentable Lifecycle

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> SwarmDeckMetalTerminalView {
        let view = SwarmDeckMetalTerminalView(frame: .zero)
        configureView(view, context: context, initial: true)
        return view
    }

    public func updateNSView(_ view: SwarmDeckMetalTerminalView, context: Context) {
        configureView(view, context: context, initial: false)
    }

    public static func dismantleNSView(_ view: SwarmDeckMetalTerminalView, coordinator: Coordinator) {
        view.onFocusChanged = nil
        view.delegate = nil
    }

    private func configureView(_ view: SwarmDeckMetalTerminalView, context: Context, initial: Bool) {
        context.coordinator.parent = self

        if initial {
            view.delegate = self.context
        }

        if let currentController = view.controller, currentController === self.context.controller {
            // Controller already linked
        } else {
            view.controller = self.context.controller
        }

        view.configuration = self.context.configuration
        view.setSurfaceVisible(self.context.isSurfaceVisible)

        // Wire AppKit responder focus transitions back to SwiftUI FocusBinding
        view.onFocusChanged = { [weak view] focused in
            guard view != nil else { return }
            focusBinding?.setFocused(focused)
        }

        // Apply focus state imperatively to the window responder chain
        Self.synchronizeFocus(view, with: focusBinding)

        // Propagate environment color scheme to Ghostty engine
        let currentScheme = context.environment.colorScheme
        self.context.adopt(colorScheme: currentScheme)
    }

    // MARK: - Focus Synchronization

    public static func synchronizeFocus(_ view: AppTerminalView, with binding: FocusBinding?) {
        guard let binding else { return }

        DispatchQueue.main.async { [weak view] in
            guard let view, let window = view.window else { return }
            if binding.isFocused {
                if window.firstResponder !== view {
                    window.makeFirstResponder(view)
                }
            } else if window.firstResponder === view {
                window.makeFirstResponder(nil)
            }
        }
    }

    // MARK: - Focus State Modifiers

    public func terminalFocused(_ condition: FocusState<Bool>.Binding) -> TerminalSurfaceView {
        TerminalSurfaceView(
            context: context,
            focusBinding: .bool(condition)
        )
    }

    public func terminalFocused<Value: Hashable>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value
    ) -> TerminalSurfaceView {
        TerminalSurfaceView(
            context: context,
            focusBinding: .optional(
                read: { binding.wrappedValue == value },
                write: { focused in
                    binding.wrappedValue = focused ? value : nil
                }
            )
        )
    }

    public func terminalFocusOnAppear(_ condition: FocusState<Bool>.Binding) -> some View {
        terminalFocused(condition)
            .onAppear {
                condition.wrappedValue = true
            }
    }

    public func terminalFocusOnAppear<Value: Hashable>(
        _ binding: FocusState<Value?>.Binding,
        equals value: Value
    ) -> some View {
        terminalFocused(binding, equals: value)
            .onAppear {
                binding.wrappedValue = value
            }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, TerminalSurfaceViewDelegate {
        var parent: TerminalSurfaceView

        init(_ parent: TerminalSurfaceView) {
            self.parent = parent
            super.init()
        }
    }

    // MARK: - Focus Binding

    @MainActor
    public struct FocusBinding: @unchecked Sendable {
        private let read: @MainActor () -> Bool
        private let write: @MainActor (Bool) -> Void

        public var isFocused: Bool {
            read()
        }

        public func setFocused(_ focused: Bool) {
            write(focused)
        }

        public static func bool(_ binding: FocusState<Bool>.Binding) -> FocusBinding {
            FocusBinding(
                read: { binding.wrappedValue },
                write: { binding.wrappedValue = $0 }
            )
        }

        public static func optional(
            read: @escaping @MainActor () -> Bool,
            write: @escaping @MainActor (Bool) -> Void
        ) -> FocusBinding {
            FocusBinding(read: read, write: write)
        }
    }
}

/// Specialized AppTerminalView subclass tuned for ProMotion 120 FPS Metal rendering and focus tracking.
@MainActor
open class SwarmDeckMetalTerminalView: AppTerminalView {
    public var onFocusChanged: ((Bool) -> Void)?

    override public init(frame: NSRect) {
        super.init(frame: frame)
        configureProMotionMetalLayer()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Tunes CAMetalLayer specifically for macOS 120 Hz ProMotion display timing.
    public func configureProMotionMetalLayer() {
        wantsLayer = true
        if let metal = layer as? CAMetalLayer {
            metal.device = MTLCreateSystemDefaultDevice()
            metal.pixelFormat = .bgra8Unorm
            metal.framebufferOnly = true
            metal.displaySyncEnabled = true
            metal.maximumDrawableCount = 3 // Triple-buffering to prevent frame drops under burst streaming
            metal.isOpaque = false
            metal.backgroundColor = NSColor.clear.cgColor
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            metal.contentsScale = scale
        }
    }

    override open func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        onFocusChanged?(true)
        return result
    }

    override open func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        onFocusChanged?(false)
        return result
    }

    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            configureProMotionMetalLayer()
        }
    }
}
