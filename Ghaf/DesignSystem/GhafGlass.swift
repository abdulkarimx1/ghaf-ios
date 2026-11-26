import SwiftUI
import UIKit
import CoreMotion
import simd
import Observation
import os

private let ghafGlassLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Ghaf", category: "glass")

struct GhafGlassStyle: Equatable {
    enum Intensity: String, CaseIterable, Identifiable { case subtle, balanced, bold; var id: String { rawValue } }
    var enabled = true
    var intensity: Intensity = .balanced
    var grain = true
    var ambientGlow = true
    var tilt = true
    /// Owner #58: thickness of the tilt-lit rim, chosen in Customization (thin / medium / thick).
    var rimWidth: CGFloat = 2.5
    static func rimWidth(_ key: String) -> CGFloat { key == "thin" ? 1 : key == "medium" ? 1.75 : 2.5 }
    static let off = GhafGlassStyle(enabled: false, intensity: .balanced, grain: false, ambientGlow: false, tilt: false)
}

private struct GhafGlassEnvironmentKey: EnvironmentKey { static let defaultValue = GhafGlassStyle.off }
extension EnvironmentValues { var ghafGlass: GhafGlassStyle { get { self[GhafGlassEnvironmentKey.self] } set { self[GhafGlassEnvironmentKey.self] = newValue } } }

struct GhafTiltFilter {
    private(set) var reference: simd_quatd?
    private var timestamp = 0.0
    private var position = SIMD2<Double>.zero
    private var velocity = SIMD2<Double>.zero

    mutating func sample(_ attitude: simd_quatd, at time: TimeInterval) -> CGPoint {
        if let reference {
            let dt = time - timestamp
            guard dt > 0 else { return CGPoint(x: position.x, y: position.y) }
            let normal = (reference.inverse * attitude).act(SIMD3(0, 0, 1))
            var target = SIMD2(Self.normalized(atan2(normal.x, normal.z)),
                               Self.normalized(asin(max(-1, min(1, -normal.y)))))
            target /= max(1, simd_length(target))
            // Exact critically damped step at 20 rad/s, independent of delivery jitter.
            let error = position - target
            let slope = velocity + 20 * error
            let decay = exp(-20 * dt)
            position = target + (error + slope * dt) * decay
            velocity = (velocity - 20 * slope * dt) * decay
            self.reference = simd_slerp(reference, attitude, 1 - exp(-dt / 2.5))
        } else {
            reference = attitude
            ghafGlassLogger.info("Tilt neutral attitude captured; reference recenter time constant 2.5 s")
        }
        timestamp = time
        return CGPoint(x: position.x, y: position.y)
    }

    static func normalized(_ angle: Double) -> Double {
        let degrees = abs(angle) * 180 / .pi
        return copysign(min(1, max(0, (degrees - 1.5) / (20 - 1.5))), angle)
    }

#if DEBUG
    static func selfCheck() {
        var filter = GhafTiltFilter()
        let neutral = simd_quatd(angle: 35 * .pi / 180, axis: SIMD3(1, 0, 0))
        assert(filter.sample(neutral, at: 0) == .zero, "Captured hand-held attitude must be neutral")
        let moved = neutral * simd_quatd(angle: 10 * .pi / 180, axis: SIMD3(1, 0, 0))
        let response = filter.sample(moved, at: 1.0 / 30)
        assert(hypot(response.x, response.y) > 0 && hypot(response.x, response.y) <= 1, "Tilt response must stay normalized")
        var settled = response
        for step in 2...180 { settled = filter.sample(moved, at: Double(step) / 30) }
        assert(hypot(settled.x, settled.y) < hypot(response.x, response.y), "Reference must slowly recenter")
        ghafGlassLogger.info("Tilt self-check passed: hand-held neutral captured and reference recentered")
    }
#endif
}

@Observable @MainActor
final class GhafTiltMotion {
    static let shared = GhafTiltMotion()
    private(set) var tilt = CGPoint.zero
    private let manager = CMMotionManager()
    private var timer: Timer?
    private var filter = GhafTiltFilter()
    private var requested = false
    private var powerObserver: NSObjectProtocol?
    private init() {
#if DEBUG
        GhafTiltFilter.selfCheck()
#endif
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
        let enabled = requested && !ProcessInfo.processInfo.isLowPowerModeEnabled && thermalAllowsMotion
#if DEBUG
        if enabled, let fixture = Self.debugAttitude {
            tilt = fixture
            ghafGlassLogger.info("Tilt fixture applied; Core Motion bypassed")
            return
        }
#endif
        guard enabled && manager.isDeviceMotionAvailable else {
            timer?.invalidate()
            timer = nil
            if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
            filter = GhafTiltFilter()
            if tilt != .zero { tilt = .zero }
            return
        }
        guard timer == nil else { return }
        let interval = 1.0 / 30
        manager.deviceMotionUpdateInterval = interval
        manager.startDeviceMotionUpdates()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        guard let motion = manager.deviceMotion else { return }
        let q = motion.attitude.quaternion
        let next = filter.sample(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w), at: motion.timestamp)
        if hypot(next.x - tilt.x, next.y - tilt.y) > 0.003 {
            tilt = next
        }
    }

#if DEBUG
    private static var debugAttitude: CGPoint? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-GhafTiltFixture"),
              let rollIndex = args.firstIndex(of: "-GhafTiltRoll"), args.indices.contains(rollIndex + 1),
              let pitchIndex = args.firstIndex(of: "-GhafTiltPitch"), args.indices.contains(pitchIndex + 1),
              let roll = Double(args[rollIndex + 1]), let pitch = Double(args[pitchIndex + 1]) else { return nil }
        let vector = CGPoint(x: GhafTiltFilter.normalized(roll * .pi / 180),
                             y: GhafTiltFilter.normalized(pitch * .pi / 180))
        let magnitude = hypot(vector.x, vector.y)
        let scale = magnitude > 1 ? 1 / magnitude : 1
        return CGPoint(x: vector.x * scale, y: vector.y * scale)
    }
#endif
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
                .overlay { GhafGlassRim(theme: theme, shape: shape, width: glass.rimWidth) }
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
    let width: CGFloat
    private var motion: GhafTiltMotion { .shared }
    var body: some View {
        let tilt = motion.tilt
        let angle = Double.pi / 2 + Double(tilt.x) * 30 * .pi / 180
        let shiftX = CGFloat(tilt.x) * 0.3
        let shiftY = CGFloat(tilt.y) * 0.3
        let start = UnitPoint(x: 0.5 - cos(angle) * 0.5 + shiftX, y: 0.5 - sin(angle) * 0.5 + shiftY)
        let end = UnitPoint(x: 0.5 + cos(angle) * 0.5 + shiftX, y: 0.5 + sin(angle) * 0.5 + shiftY)
        let light = theme.isDark ? theme.primaryText : theme.glow
        let gradient = LinearGradient(colors: [light.opacity(0.22), light.opacity(0.10),
                                               light.opacity(0.025), light.opacity(0.07)],
                                      startPoint: start, endPoint: end)
        shape.strokeBorder(gradient, lineWidth: width)
            .blur(radius: width * 0.48)
            .clipShape(shape)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct GhafGlassPreview: View {
    let theme: GhafTheme
    var arabic = false
    var body: some View {
        HStack { VStack(alignment: .leading, spacing: 8) { Text(arabic ? "شهري" : "Monthly").font(.caption).foregroundStyle(theme.secondaryText); Text(GhafFormat.shownMoney(2340, currency: "AED", languageCode: arabic ? "ar" : "en")).font(.title2.bold()).foregroundStyle(theme.primaryText); Image(systemName: "waveform.path").font(.title2).foregroundStyle(theme.accent) }; Spacer() }
            .padding(16).frame(maxWidth: .infinity).modifier(GhafGlassSurface(theme: theme, radius: 18))
    }
}

struct GhafTiltLifecycle: ViewModifier {
    @AppStorage("ghaf.glass.enabled") private var enabled = true
    @AppStorage("ghaf.glass.intensity") private var intensity = "balanced"
    @AppStorage("ghaf.glass.grain") private var grain = true
    @AppStorage("ghaf.glass.glow") private var glow = true
    @AppStorage("ghaf.glass.tilt") private var tilt = true
    @AppStorage("ghaf.glass.rim") private var rim = "thick"
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
    private var style: GhafGlassStyle { GhafGlassStyle(enabled: enabled && !reduceTransparency, intensity: .init(rawValue: intensity) ?? .balanced, grain: grain, ambientGlow: glow, tilt: tilt && !reduceMotion && !reduceTransparency,
                                                rimWidth: GhafGlassStyle.rimWidth(rim)) }
}
