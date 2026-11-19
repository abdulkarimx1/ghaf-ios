import SwiftUI
import UIKit
import CoreMotion
import Observation
import os

struct GhafGlassStyle: Equatable {
    enum Intensity: String, CaseIterable, Identifiable { case subtle, balanced, bold; var id: String { rawValue } }
    var enabled = true
    var intensity: Intensity = .balanced
    var grain = true
    var ambientGlow = true
    var tilt = true
    static let off = GhafGlassStyle(enabled: false, intensity: .balanced, grain: false, ambientGlow: false, tilt: false)
}

private struct GhafGlassEnvironmentKey: EnvironmentKey { static let defaultValue = GhafGlassStyle.off }
extension EnvironmentValues { var ghafGlass: GhafGlassStyle { get { self[GhafGlassEnvironmentKey.self] } set { self[GhafGlassEnvironmentKey.self] = newValue } } }

@Observable @MainActor
final class GhafTiltMotion {
    static let shared = GhafTiltMotion()
    private(set) var tilt = CGPoint.zero
    private let manager = CMMotionManager()
    private let queue: OperationQueue = { let q = OperationQueue(); q.name = "GhafTiltMotion"; q.maxConcurrentOperationCount = 1; q.qualityOfService = .utility; return q }()
    private var reference: CMAttitude?
    private var filtered = CGPoint.zero
    private var running = false
    private var requested = false
    private var powerObserver: NSObjectProtocol?
    private init() {
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reevaluate() } }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reevaluate() } }
    }
    func update(enabled: Bool) {
        requested = enabled
        reevaluate()
    }
    private func reevaluate() {
        let thermalAllowsMotion: Bool
        switch ProcessInfo.processInfo.thermalState { case .nominal, .fair: thermalAllowsMotion = true; case .serious, .critical: thermalAllowsMotion = false; @unknown default: thermalAllowsMotion = false }
        let shouldRun = requested && manager.isDeviceMotionAvailable && !ProcessInfo.processInfo.isLowPowerModeEnabled && thermalAllowsMotion
        guard shouldRun != running else { return }
        running = shouldRun
        if shouldRun {
            manager.deviceMotionUpdateInterval = 1.0 / 30.0
            manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let motion else { return }
                if self?.reference == nil { self?.reference = motion.attitude.copy() as? CMAttitude }
                let attitude = motion.attitude
                if let reference = self?.reference { attitude.multiply(byInverseOf: reference) }
                let target = CGPoint(x: max(-0.25, min(0.25, attitude.roll)), y: max(-0.25, min(0.25, attitude.pitch)))
                Task { @MainActor [weak self] in
                    guard let self, self.running else { return }
                    let next = CGPoint(x: self.filtered.x + (target.x - self.filtered.x) * 0.15, y: self.filtered.y + (target.y - self.filtered.y) * 0.15)
                    if abs(next.x - self.filtered.x) > 0.02 || abs(next.y - self.filtered.y) > 0.02 {
                        self.filtered = next; self.tilt = CGPoint(x: next.x / 0.25, y: next.y / 0.25)
                    }
                }
            }
            Logger.ghafGlass.debug("Tilt motion started")
        } else {
            manager.stopDeviceMotionUpdates(); reference = nil; filtered = .zero; tilt = .zero
            Logger.ghafGlass.debug("Tilt motion stopped")
        }
    }
}

private extension Logger {
    static let ghafGlass = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ghaf", category: "glass")
}

enum GhafGlassGrain {
    static let image: UIImage = {
        let size = 128
        var seed: UInt32 = 0x47484146
        let bytes = (0..<(size * size)).map { _ -> UInt8 in seed = 1664525 &* seed &+ 1013904223; return UInt8(seed >> 24) }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: size, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
        return UIImage(cgImage: image)
    }()
}

struct GhafGlassSurface: ViewModifier {
    let theme: GhafTheme
    var radius: CGFloat
    var hero = false
    var fallback: Color? = nil
    @Environment(\.ghafGlass) private var glass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    func body(content: Content) -> some View {
        let active = glass.enabled && !reduceTransparency
        let opacity: Double = glass.intensity == .subtle ? 0.35 : glass.intensity == .balanced ? 0.45 : 0.55
        let material: Material = glass.intensity == .subtle ? .ultraThin : glass.intensity == .balanced ? .thin : .regular
        content.background {
            if active {
                ZStack {
                    shape.fill(material)
                    shape.fill((theme.isDark ? theme.surface : Color.white).opacity(opacity))
                    if hero { LinearGradient(colors: [theme.accent.opacity(0.55), .clear], startPoint: .bottom, endPoint: .top).frame(height: 100).frame(maxHeight: .infinity, alignment: .bottom).clipShape(shape) }
                    GhafGlassSheen(theme: theme).clipShape(shape)
                    if glass.grain { Image(uiImage: GhafGlassGrain.image).resizable(resizingMode: .tile).opacity(theme.isDark ? 0.05 : 0.035).blendMode(.overlay).allowsHitTesting(false).clipShape(shape) }
                }
                .overlay { GhafGlassRim(theme: theme, shape: shape, contrast: contrast) }
                .shadow(color: theme.isDark ? .clear : .black.opacity(0.08), radius: 18, x: 0, y: 8)
            } else {
                shape.fill(fallback ?? theme.surface).shadow(color: theme.shadow, radius: 14, x: 0, y: 6)
                    .overlay { if theme.isDark { shape.stroke(theme.outline, lineWidth: 1) } }
            }
        }
    }
}

private struct GhafGlassRim: View {
    let theme: GhafTheme
    let shape: RoundedRectangle
    let contrast: ColorSchemeContrast
    private var motion: GhafTiltMotion { .shared }
    var body: some View {
        let tilt = motion.tilt
        let angle = Double.pi / 4 + Double(tilt.x) * 40 * .pi / 180
        let shift = CGFloat(tilt.y) * 0.18
        let start = UnitPoint(x: 0.5 - cos(angle) * 0.5 + shift, y: 0.5 - sin(angle) * 0.5)
        let end = UnitPoint(x: 0.5 + cos(angle) * 0.5 + shift, y: 0.5 + sin(angle) * 0.5)
        shape.strokeBorder(LinearGradient(colors: theme.isDark ? [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.02), .white.opacity(0.18)] : [.white.opacity(0.9), .black.opacity(0.06), .black.opacity(0.02), .white.opacity(0.5)], startPoint: start, endPoint: end), lineWidth: contrast == .increased ? 1.6 : 1)
    }
}

struct GhafShapeRim<S: Shape>: View {
    let isDark: Bool
    let shape: S
    let contrast: ColorSchemeContrast

    init(theme: GhafTheme, shape: S, contrast: ColorSchemeContrast) {
        self.isDark = theme.isDark
        self.shape = shape
        self.contrast = contrast
    }

    init(isDark: Bool, shape: S, contrast: ColorSchemeContrast) {
        self.isDark = isDark
        self.shape = shape
        self.contrast = contrast
    }

    private var motion: GhafTiltMotion { .shared }
    var body: some View {
        let tilt = motion.tilt
        let angle = Double.pi / 4 + Double(tilt.x) * 40 * .pi / 180
        let shift = CGFloat(tilt.y) * 0.18
        let start = UnitPoint(x: 0.5 - cos(angle) * 0.5 + shift, y: 0.5 - sin(angle) * 0.5)
        let end = UnitPoint(x: 0.5 + cos(angle) * 0.5 + shift, y: 0.5 + sin(angle) * 0.5)
        shape.stroke(LinearGradient(colors: isDark ? [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.02), .white.opacity(0.18)] : [.white.opacity(0.9), .black.opacity(0.06), .black.opacity(0.02), .white.opacity(0.5)], startPoint: start, endPoint: end), lineWidth: contrast == .increased ? 1.6 : 1)
    }
}

private struct GhafGlassSheen: View {
    let theme: GhafTheme
    var body: some View {
        RadialGradient(colors: [.white.opacity(theme.isDark ? 0.06 : 0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 150)
    }
}

struct GhafGlassPreview: View {
    let theme: GhafTheme
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 8) { Text("Monthly").font(.caption).foregroundStyle(theme.secondaryText); Text("AED 2,340").font(.title2.bold()).foregroundStyle(theme.primaryText); Image(systemName: "waveform.path").font(.title2).foregroundStyle(theme.accent).shadow(color: theme.glow, radius: 6) }; Spacer() }
            .padding(16).frame(maxWidth: .infinity).modifier(GhafGlassSurface(theme: theme, radius: 18, hero: true))
    }
}

struct GhafTiltLifecycle: ViewModifier {
    @AppStorage("ghaf.glass.enabled") private var enabled = true
    @AppStorage("ghaf.glass.intensity") private var intensity = "balanced"
    @AppStorage("ghaf.glass.grain") private var grain = true
    @AppStorage("ghaf.glass.glow") private var glow = true
    @AppStorage("ghaf.glass.tilt") private var tilt = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.environment(\.ghafGlass, style)
            .onAppear { refresh() }
            .onChange(of: enabled) { _, _ in refresh() }
            .onChange(of: tilt) { _, _ in refresh() }
            .onChange(of: intensity) { _, _ in refresh() }
            .onChange(of: grain) { _, _ in refresh() }
            .onChange(of: glow) { _, _ in refresh() }
            .onChange(of: scenePhase) { _, _ in refresh() }
            .onChange(of: reduceMotion) { _, _ in refresh() }
            .onChange(of: reduceTransparency) { _, _ in refresh() }
    }
    private func refresh() { GhafTiltMotion.shared.update(enabled: enabled && tilt && scenePhase == .active && !reduceMotion && !reduceTransparency) }
    private var style: GhafGlassStyle { GhafGlassStyle(enabled: enabled && !reduceTransparency, intensity: .init(rawValue: intensity) ?? .balanced, grain: grain, ambientGlow: glow, tilt: tilt && !reduceMotion && !reduceTransparency) }
}
