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
    private let deadZone = 0.0262 // 1.5 degrees
    private var powerObserver: NSObjectProtocol?
    private init() {
        powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reevaluate() } }
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.reevaluate() } }
    }
    func update(enabled: Bool) {
        requested = enabled
#if DEBUG
        if enabled, let fixture = Self.debugAttitude {
            manager.stopDeviceMotionUpdates()
            running = false
            reference = nil
            filtered = fixture
            tilt = fixture
            return
        }
#endif
        reevaluate()
    }
    private func reevaluate() {
        let thermalAllowsMotion: Bool
        switch ProcessInfo.processInfo.thermalState { case .nominal, .fair: thermalAllowsMotion = true; case .serious, .critical: thermalAllowsMotion = false; @unknown default: thermalAllowsMotion = false }
        let shouldRun = requested && manager.isDeviceMotionAvailable && !ProcessInfo.processInfo.isLowPowerModeEnabled && thermalAllowsMotion
        guard shouldRun != running else { return }
        running = shouldRun
        if shouldRun {
            manager.deviceMotionUpdateInterval = 1.0 / 60.0
            manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
                guard let motion else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.running else { return }
                    guard let attitude = motion.attitude.copy() as? CMAttitude else { return }
                    if self.reference == nil { self.reference = attitude.copy() as? CMAttitude }
                    if let reference = self.reference { attitude.multiply(byInverseOf: reference) }
                    let target = CGPoint(x: Self.normalized(attitude.roll, deadZone: self.deadZone),
                                         y: Self.normalized(attitude.pitch, deadZone: self.deadZone))
                    let next = CGPoint(x: self.filtered.x + (target.x - self.filtered.x) * 0.12,
                                       y: self.filtered.y + (target.y - self.filtered.y) * 0.12)
                    if abs(next.x - self.filtered.x) > 0.003 || abs(next.y - self.filtered.y) > 0.003 {
                        self.filtered = next
                        let magnitude = hypot(next.x, next.y)
                        let scale = magnitude > 1 ? 1 / magnitude : 1
                        self.tilt = CGPoint(x: next.x * scale, y: next.y * scale)
                    }
                }
            }
            Logger.ghafGlass.debug("Tilt motion started")
        } else {
            manager.stopDeviceMotionUpdates(); reference = nil; filtered = .zero; tilt = .zero
            Logger.ghafGlass.debug("Tilt motion stopped")
        }
    }

    private static func normalized(_ angle: Double, deadZone: Double) -> Double {
        let magnitude = abs(angle)
        guard magnitude > deadZone else { return 0 }
        return copysign(min((magnitude - deadZone) / (Double.pi / 6 - deadZone), 1), angle)
    }

#if DEBUG
    private static var debugAttitude: CGPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-GhafTiltFixture"),
              let rollIndex = args.firstIndex(of: "-GhafTiltRoll"), args.indices.contains(rollIndex + 1),
              let pitchIndex = args.firstIndex(of: "-GhafTiltPitch"), args.indices.contains(pitchIndex + 1),
              let roll = Double(args[rollIndex + 1]), let pitch = Double(args[pitchIndex + 1]) else { return nil }
        let vector = CGPoint(x: normalized(roll * .pi / 180, deadZone: 0.0262),
                             y: normalized(pitch * .pi / 180, deadZone: 0.0262))
        let magnitude = hypot(vector.x, vector.y)
        let scale = magnitude > 1 ? 1 / magnitude : 1
        return CGPoint(x: vector.x * scale, y: vector.y * scale)
    }
#endif
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
    var fallback: Color? = nil
    @Environment(\.ghafGlass) private var glass
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }
    func body(content: Content) -> some View {
        let active = glass.enabled && !reduceTransparency
        let trueGlass = theme.name == "Graphite"
        let opacity: Double = glass.intensity == .subtle ? 0.35 : glass.intensity == .balanced ? 0.45 : 0.55
        let material: Material = glass.intensity == .subtle ? .ultraThin : glass.intensity == .balanced ? .thin : .regular
        content.background {
            if active {
                ZStack {
                    if trueGlass {
                        shape.fill(material)
                        shape.fill((fallback ?? (theme.isDark ? theme.surface : Color.white)).opacity(fallback == nil ? opacity : 0.82))
                    } else {
                        shape.fill(fallback ?? theme.surface)
                        shape.fill(theme.accent.opacity(theme.isDark ? 0.07 : 0.04))
                    }
                    if glass.grain { Image(uiImage: GhafGlassGrain.image).resizable(resizingMode: .tile).opacity(theme.isDark ? 0.05 : 0.035).blendMode(.overlay).allowsHitTesting(false).clipShape(shape) }
                }
                .overlay {
                    GhafGlassRim(theme: theme, shape: shape).blur(radius: 3).opacity(0.6).clipShape(shape)
                }
                .overlay { GhafGlassRim(theme: theme, shape: shape) }
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
    private var motion: GhafTiltMotion { .shared }
    var body: some View {
        let tilt = motion.tilt
        let angle = Double.pi / 2 + Double(tilt.x) * 30 * .pi / 180
        let shiftX = CGFloat(tilt.x) * 0.3
        let shiftY = CGFloat(tilt.y) * 0.3
        let start = UnitPoint(x: 0.5 - cos(angle) * 0.5 + shiftX, y: 0.5 - sin(angle) * 0.5 + shiftY)
        let end = UnitPoint(x: 0.5 + cos(angle) * 0.5 + shiftX, y: 0.5 + sin(angle) * 0.5 + shiftY)
        shape.strokeBorder(LinearGradient(colors: theme.isDark ? [.white, .white.opacity(0.12), .white.opacity(0.03), .white.opacity(0.25)] : [theme.glow, theme.glow.opacity(0.18), theme.outline], startPoint: start, endPoint: end), lineWidth: 1.2)
    }
}

struct GhafShapeRim<S: Shape>: View {
    let theme: GhafTheme
    let shape: S

    init(theme: GhafTheme, shape: S) {
        self.theme = theme
        self.shape = shape
    }

    private var motion: GhafTiltMotion { .shared }
    var body: some View {
        let tilt = motion.tilt
        let angle = Double.pi / 2 + Double(tilt.x) * 30 * .pi / 180
        let shiftX = CGFloat(tilt.x) * 0.3
        let shiftY = CGFloat(tilt.y) * 0.3
        let start = UnitPoint(x: 0.5 - cos(angle) * 0.5 + shiftX, y: 0.5 - sin(angle) * 0.5 + shiftY)
        let end = UnitPoint(x: 0.5 + cos(angle) * 0.5 + shiftX, y: 0.5 + sin(angle) * 0.5 + shiftY)
        shape.stroke(LinearGradient(colors: theme.isDark ? [.white, .white.opacity(0.12), .white.opacity(0.03), .white.opacity(0.25)] : [theme.glow, theme.glow.opacity(0.18), theme.outline], startPoint: start, endPoint: end), lineWidth: 1.2)
    }
}

struct GhafGlassPreview: View {
    let theme: GhafTheme
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 8) { Text("Monthly").font(.caption).foregroundStyle(theme.secondaryText); Text("AED 2,340").font(.title2.bold()).foregroundStyle(theme.primaryText); Image(systemName: "waveform.path").font(.title2).foregroundStyle(theme.accent) }; Spacer() }
            .padding(16).frame(maxWidth: .infinity).modifier(GhafGlassSurface(theme: theme, radius: 18))
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
