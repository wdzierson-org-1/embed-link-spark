import SwiftUI
import CoreMotion
import StashKit

/// The homepage's liquid ASCII field, drawn natively behind an opaque sign-in window.
/// Motion changes the fluid's forces, not the form's position. Sensors and frames run
/// only while this surface is visible, active, and the user is not entering credentials.
struct ASCIIPoolBackdrop: View {
    var isEditing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pool = ASCIIPoolDriver()

    private var runs: Bool { scenePhase == .active && !StashMotion.reduced(reduceMotion) && !isEditing }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StashColor.spot
                PoolPaperTexture()
                ASCIIPoolCanvas(particles: pool.particles, worldWidth: pool.worldWidth)
            }
            .onChange(of: geometry.size, initial: true) { _, size in pool.resize(size) }
            .task(id: runs) {
                guard runs else { return }
                await pool.run()
            }
            .onDisappear { pool.stopMotion() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Pull-based Core Motion avoids a second stream of view invalidations. No sensor
/// data is stored or transmitted. See Apple's CMMotionManager/startDeviceMotionUpdates.
@MainActor @Observable
private final class ASCIIPoolDriver {
    var particles: [ASCIIPoolSimulation.Particle] = []
    private(set) var worldWidth = 1.4
    @ObservationIgnored private var simulation: ASCIIPoolSimulation?
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var filteredX = 0.0
    @ObservationIgnored private var filteredY = -9.81
    @ObservationIgnored private var runID: UUID?

    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let width = 3 * Double(size.width / size.height)
        guard simulation == nil || abs(width - worldWidth) > 0.03 else { return }
        worldWidth = width
        simulation = ASCIIPoolSimulation(width: width, height: 3, maxParticles: 600)
        // Establish a fluid surface before its first visible frame, including the
        // meaningful still shown with Reduce Motion or an unavailable sensor.
        for index in 0..<12 {
            simulation?.step(deltaTime: 1.0 / 60, gravityX: 2.4 * sin(Double(index) / 9))
        }
        particles = simulation?.particles ?? []
    }

    func run() async {
        let id = UUID()
        runID = id
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 30
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
        defer { if runID == id { stopMotion() } }
        let clock = ContinuousClock()
        var previous = clock.now
        while !Task.isCancelled && runID == id {
            let interval = ProcessInfo.processInfo.isLowPowerModeEnabled ? 1.0 / 15 : 1.0 / 30
            guard !Task.isCancelled, runID == id else { return }
            let now = clock.now
            let duration = previous.duration(to: now).components
            let dt = min(1.0 / 15, max(0, Double(duration.seconds) + Double(duration.attoseconds) / 1e18))
            previous = now
            elapsed += dt
            let force = gravity()
            // Light filtering removes sensor chatter, while an actual movement still
            // reaches the liquid promptly. User acceleration reinforces its direction.
            let blend = 1 - exp(-dt * 9)
            filteredX += (force.x - filteredX) * blend
            filteredY += (force.y - filteredY) * blend
            simulation?.step(deltaTime: dt, gravityX: filteredX, gravityY: filteredY)
            particles = simulation?.particles ?? []
            // Rendering/physics consumes part of the frame budget, not an extra
            // delay added to it. A slow frame never schedules unbounded catch-up.
            do { try await clock.sleep(until: now.advanced(by: .seconds(interval))) } catch { return }
        }
    }

    func stopMotion() {
        motion.stopDeviceMotionUpdates()
        runID = nil
    }

    private func gravity() -> (x: Double, y: Double) {
        #if DEBUG
        // Deterministic injected motion for simulator verification. Never present in Release.
        if ProcessInfo.processInfo.arguments.contains("--uitest-pool-tilt-right") { return (9, -9.81) }
        if ProcessInfo.processInfo.arguments.contains("--uitest-pool-tilt-left") { return (-9, -9.81) }
        if ProcessInfo.processInfo.arguments.contains("--uitest-pool-motion-demo") { return (sin(elapsed * 1.2) * 10, -9.81) }
        #endif
        guard let sample = motion.deviceMotion else {
            // The simulator has no gyroscope; a small, slow current makes the native
            // rendering reviewable without pretending a mouse drag is phone motion.
            return (sin(elapsed * 0.6) * 0.55, -9.81)
        }
        let orientation = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
                           as? UIWindowScene)?.interfaceOrientation ?? .portrait
        func screenAxes(_ x: Double, _ y: Double) -> (x: Double, y: Double) {
            switch orientation {
            // UIInterfaceOrientation's landscape names are opposite to
            // UIDeviceOrientation: interface-left puts the Home edge on the left.
            case .landscapeLeft: return (y, -x)
            case .landscapeRight: return (-y, x)
            case .portraitUpsideDown: return (-x, -y)
            default: return (x, y)
            }
        }
        let tilt = screenAxes(sample.gravity.x, sample.gravity.y)
        let movement = screenAxes(sample.userAcceleration.x, sample.userAcceleration.y)
        // Keep a downward pull even with the phone lying flat. Tilting tips the
        // surface; moving it pushes glyphs in that same screen-space direction.
        return (max(-14, min(14, tilt.x * 12 + movement.x * 18)),
                max(-22, min(8, -9.81 + movement.y * 20)))
    }
}

private struct ASCIIPoolCanvas: View {
    let particles: [ASCIIPoolSimulation.Particle]
    let worldWidth: Double
    private static let ramp = Array(" ·:-~=+*#%@")

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let cell = 13.0
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            guard columns > 0, rows > 0, worldWidth > 0 else { return }
            var counts = [Int](repeating: 0, count: columns * rows)
            var speeds = [Double](repeating: 0, count: columns * rows)
            var surface = [Int](repeating: rows, count: columns)
            for particle in particles {
                let column = Int(particle.x / worldWidth * size.width / cell)
                let row = Int((1 - particle.y / 3) * size.height / cell)
                guard column >= 0, column < columns, row >= 0, row < rows else { continue }
                let index = row * columns + column
                counts[index] += 1
                speeds[index] += abs(particle.velocityX) + abs(particle.velocityY)
                surface[column] = min(surface[column], row)
            }
            // Resolve each glyph once per frame; only density/speed picks which glyph
            // to draw. This is the web's ramp and its depth/surface weighting.
            let glyphs = Self.ramp.map {
                context.resolve(Text(String($0)).font(.custom("DepartureMono-Regular", fixedSize: 11))
                    .foregroundColor(.black))
            }
            let expected = max(1, Double(particles.count) / Double(columns * rows) / 0.35)
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = row * columns + column
                    guard counts[index] > 0 else { continue }
                    let speed = speeds[index] / Double(counts[index])
                    let depth = min(1, Double(row - surface[column]) / 16)
                    let jitter = Double(((column &* 73856093) ^ (row &* 19349663)) & 1023) / 1023 - 0.5
                    var weight = 0.1 + 0.4 * depth + 0.3 * min(speed / 1.4, 1.6)
                    weight += 0.08 * (Double(counts[index]) / expected - 1) + 0.16 * jitter
                    if surface[column] == row { weight += 0.3 }
                    let glyph = max(1, min(Self.ramp.count - 1, 1 + Int(weight * 9)))
                    context.opacity = 0.62 + 0.38 * min(1, max(0, weight * 1.5))
                    context.draw(glyphs[glyph], at: CGPoint(x: (Double(column) + 0.5) * cell,
                                                          y: (Double(row) + 0.5) * cell))
                }
            }
        }
    }
}

/// Static dots and Bayer stipple, separate from the fluid's frame invalidations.
private struct PoolPaperTexture: View {
    private let bayer = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

    var body: some View {
        Canvas { context, size in
            let top = size.height * 0.65
            var dots = Path()
            for y in stride(from: 2.0, to: top - 60, by: 4) {
                for x in stride(from: 2.0, to: size.width, by: 4) {
                    dots.addRect(CGRect(x: x, y: y, width: 0.7, height: 0.7))
                }
            }
            context.fill(dots, with: .color(.black.opacity(0.08)))
            var stipple = Path()
            for y in stride(from: 0.0, to: top, by: 3) {
                for x in stride(from: 0.0, to: size.width, by: 3) {
                    var density = 0.0
                    for (cx, cy, radius) in [(size.width * 0.96, size.height * 0.12, size.width * 0.36),
                                             (size.width * 0.02, size.height * 0.52, size.width * 0.28)] {
                        let dx = (x - cx) / radius, dy = (y - cy) / radius
                        let r = hypot(dx, dy)
                        let body = 1 - smoothstep(0.8, 1, r)
                        let shade = max(0, min(1, 0.45 - 0.55 * dx + 0.65 * dy))
                        let dust = 0.06 * (1 - smoothstep(1, 1.5, r))
                        density = max(density, body * (0.06 + 0.94 * shade) + dust)
                    }
                    density *= 1 - smoothstep(top - 160, top - 12, y)
                    let threshold = (Double(bayer[(Int(y / 3) & 3) * 4 + (Int(x / 3) & 3)]) + 0.5) / 16
                    if density > threshold { stipple.addRect(CGRect(x: x, y: y, width: 1.5, height: 1.5)) }
                }
            }
            context.fill(stipple, with: .color(.black.opacity(0.22)))
        }
    }

    private func smoothstep(_ a: Double, _ b: Double, _ value: Double) -> Double {
        let t = max(0, min(1, (value - a) / (b - a)))
        return t * t * (3 - 2 * t)
    }
}
