import Combine
import SwiftUI
import AppKit

// MARK: - HUD Window Controller

class HUDWindowController: NSObject {

    private var window: NSWindow?
    private weak var appState: AppState?
    private let windowSize = NSSize(width: 220, height: 100)

    init(appState: AppState) {
        self.appState = appState
        super.init()
    }

    /// Builds the NSPanel and SwiftUI view before the first hotkey press without
    /// showing the window. This removes the largest UI cold start from the hotkey path.
    func prepare() {
        assert(Thread.isMainThread, "HUD muss auf dem Main-Thread vorbereitet werden")
        _ = preparedWindow()
    }

    func show() {
        assert(Thread.isMainThread, "HUD muss auf dem Main-Thread angezeigt werden")
        guard let hudWindow = preparedWindow() else { return }
        positionWindow(hudWindow, width: windowSize.width, height: windowSize.height)
        hudWindow.orderFront(nil)
    }

    private func preparedWindow() -> NSWindow? {
        if let window { return window }
        guard let appState else { return nil }

        // Window intentionally much larger than the capsule (144×36):
        // SwiftUI shadows have a Gaussian falloff that reaches up to ~1.5 × radius
        // (so with radius 14 and y-offset 4 a good 25 px downward). Without enough
        // margin the window edge clips the shadow → visible edge.
        // 220×100 → 32 px vertical / 38 px horizontal room. Enough headroom in all directions.
        let hudWindow = NSPanel(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        hudWindow.isOpaque           = false
        hudWindow.backgroundColor    = .clear
        hudWindow.hasShadow          = false
        hudWindow.ignoresMouseEvents = true
        hudWindow.level              = .floating
        hudWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let content = HUDView()
            .environmentObject(appState)
            .frame(width: windowSize.width, height: windowSize.height)

        let hosting = NSHostingController(rootView: content)
        hosting.view.frame = NSRect(origin: .zero, size: windowSize)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor

        hudWindow.contentViewController = hosting
        positionWindow(hudWindow, width: windowSize.width, height: windowSize.height)
        self.window = hudWindow
        return hudWindow
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func positionWindow(_ w: NSWindow, width: CGFloat, height: CGFloat) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let sf = screen.visibleFrame
        // Visually the capsule center should sit ~80 px above the bottom screen edge.
        // Since the capsule is centered in the window, the window origin has to be shifted
        // down by half the window height, otherwise the pill moves up
        // with a larger window.
        let targetCapsuleCenterY: CGFloat = 80
        w.setFrameOrigin(NSPoint(
            x: sf.midX - width  / 2,
            y: sf.minY + targetCapsuleCenterY - height / 2
        ))
    }
}

// MARK: - HUD SwiftUI View

struct HUDView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) private var colorScheme

    /// Content color for dots and waveform – adapts to the system appearance.
    /// Pure white in Dark Mode, a dark anthracite in Light Mode
    /// (not pure black – looks more pleasant on light material).
    private var contentColor: Color {
        colorScheme == .dark
            ? .white
            : Color(NSColor(white: 0.10, alpha: 1.0))
    }

    /// Subtle outline – slightly stronger in Light Mode so the pill
    /// is clearly delineated on a white background as well.
    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.12)
    }

    /// Subtler in Light Mode, stronger in Dark Mode – otherwise
    /// the dark shadow overwhelms the light capsule.
    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.35)
            : Color.black.opacity(0.14)
    }

    var body: some View {
        ZStack {
            if appState.signalWarning {
                Text("No speech signal")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
            } else if appState.isMicReady {
                WaveformBarsView(level: appState.audioLevel, color: contentColor)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.85)),
                        removal:   .opacity
                    ))
            } else {
                DotsLoadingView(color: contentColor)
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal:   .opacity.combined(with: .scale(scale: 0.85))
                    ))
            }
        }
        .animation(.spring(duration: 0.3), value: appState.isMicReady)
        .padding(.horizontal, 14)
        .frame(width: 144, height: 36)
        .background {
            // System material: adapts automatically to Light/Dark, light vibrancy blur.
            // Feels Apple-like and is visible on any background color.
            Capsule()
                .fill(.regularMaterial)
                .overlay(
                    Capsule().strokeBorder(strokeColor, lineWidth: 0.5)
                )
                .shadow(color: shadowColor, radius: 14, y: 4)
        }
        // Enough margin so the shadow is not clipped at the window edge.
        // Window is 220×100, capsule 144×36 → 38 px horizontal / 32 px vertical room.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
    }
}

// MARK: - Dots (Connecting)

struct DotsLoadingView: View {
    let color: Color
    @State private var phase = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    // Much more muted than the waveform bars (0.9 content color)
                    // → clearly recognizable as "not ready yet"
                    .fill(color.opacity(phase ? 0.42 : 0.12))
                    .frame(width: 4, height: 4)
                    .scaleEffect(phase ? 1.0 : 0.65)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: - Waveform Bars (Canvas – no layout calculations, no jitter)

struct WaveformBarsView: View {
    let level: Float
    let color: Color

    private let barCount = 9
    @State private var heights:    [Double] = Array(repeating: 3, count: 9)
    @State private var phases:     [Double] = (0..<9).map { _ in Double.random(in: 0...2 * .pi) }
    @State private var timerActive = false

    // Timer only starts while the view is visible (onAppear/onDisappear).
    private let timer = Timer.publish(every: 0.033, on: .main, in: .common).autoconnect()

    var body: some View {
        Canvas { context, size in
            let barW: Double = 3
            let gap:  Double = 3
            let total = Double(barCount) * barW + Double(barCount - 1) * gap
            let x0    = (size.width - total) / 2

            for i in 0..<barCount {
                let h  = heights[i]
                let x  = x0 + Double(i) * (barW + gap)
                let y  = (size.height - h) / 2
                context.fill(
                    Path(roundedRect: CGRect(x: x, y: y, width: barW, height: h),
                         cornerRadius: 1.5),
                    with: .color(color.opacity(0.9))
                )
            }
        }
        .onReceive(timer) { _ in if timerActive { updateBars() } }
        .onAppear  { timerActive = true  }
        .onDisappear { timerActive = false }
    }

    private func updateBars() {
        let center = barCount / 2
        let lvl    = Double(level)

        for i in 0..<barCount {
            let dist   = abs(i - center)
            let spread = max(0.2, 1.0 - Double(dist) * 0.18)
            // Small, consistent phase increment → no random stutter
            phases[i] += Double.random(in: 0.08...0.16)
            let noise  = (sin(phases[i]) + 1) / 2

            let target: Double = lvl < 0.01
                ? 2 + noise * 4 * spread
                : 3 + lvl * 26 * spread * (0.5 + noise * 0.9)

            // Smoother lerp at 30 fps: bars follow the target more evenly
            heights[i] = heights[i] * 0.75 + min(target, 26) * 0.25
        }
    }
}
