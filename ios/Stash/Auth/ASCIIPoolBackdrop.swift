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
    @State private var statusBarHeight: CGFloat = 54

    private var runs: Bool { scenePhase == .active && !StashMotion.reduced(reduceMotion) && !isEditing }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                StashColor.spot
                PoolPaperTexture()
                ASCIIPoolCanvas(particles: pool.particles, worldWidth: pool.worldWidth,
                                particleRadius: pool.particleRadius, statusBarHeight: statusBarHeight)
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                pool.resize(size)
                if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                    statusBarHeight = scene.statusBarManager?.statusBarFrame.height ?? 54
                }
            }
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
    private(set) var particleRadius = 0.02
    @ObservationIgnored private var simulation: ASCIIPoolSimulation?
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private var elapsed = 0.0
    @ObservationIgnored private var motionResponse = ASCIIPoolMotion()
    @ObservationIgnored private var runID: UUID?

    func resize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let width = 3 * Double(size.width / size.height)
        guard simulation == nil || abs(width - worldWidth) > 0.03 else { return }
        worldWidth = width
        simulation = ASCIIPoolSimulation(width: width, height: 3, maxParticles: 600)
        particleRadius = simulation?.particleRadius ?? 0.02
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
            let force = gravity(deltaTime: dt)
            simulation?.step(deltaTime: dt, gravityX: force.x, gravityY: force.y)
            particles = simulation?.particles ?? []
            // Rendering/physics consumes part of the frame budget, not an extra
            // delay added to it. A slow frame never schedules unbounded catch-up.
            do { try await clock.sleep(until: now.advanced(by: .seconds(interval))) } catch { return }
        }
    }

    func stopMotion() {
        motion.stopDeviceMotionUpdates()
        motionResponse = ASCIIPoolMotion()
        runID = nil
    }

    private func gravity(deltaTime: Double) -> ASCIIPoolMotion.Vector {
        #if DEBUG
        // Simulator samples enter the SAME sensor-to-force path as Core Motion.
        // A clockwise turn has negative z angular velocity in device coordinates.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--uitest-pool-tilt-right") {
            return motionResponse.update(gravityX: 0.8, gravityY: -0.6, rotationRateZ: 0, deltaTime: deltaTime)
        }
        if arguments.contains("--uitest-pool-tilt-left") {
            return motionResponse.update(gravityX: -0.8, gravityY: -0.6, rotationRateZ: 0, deltaTime: deltaTime)
        }
        if arguments.contains("--uitest-pool-upside-down") {
            return motionResponse.update(gravityX: 0, gravityY: 1, rotationRateZ: 0, deltaTime: deltaTime)
        }
        if arguments.contains("--uitest-pool-gyro-clockwise") || arguments.contains("--uitest-pool-gyro-counterclockwise") {
            let rate = arguments.contains("--uitest-pool-gyro-clockwise") ? -2.0 : 2.0
            return motionResponse.update(gravityX: 0, gravityY: 0, rotationRateZ: rate, deltaTime: deltaTime)
        }
        if arguments.contains("--uitest-pool-motion-demo") {
            let angle = 1.15 * sin(elapsed * 0.85)
            return motionResponse.update(gravityX: sin(angle), gravityY: -cos(angle),
                                         rotationRateZ: -1.15 * 0.85 * cos(elapsed * 0.85), deltaTime: deltaTime)
        }
        #endif
        guard let sample = motion.deviceMotion else {
            // The simulator has no gyroscope; a small, slow current makes the native
            // rendering reviewable without pretending a mouse drag is phone motion.
            return motionResponse.update(gravityX: sin(elapsed * 0.6) * 0.045,
                                         gravityY: -1, rotationRateZ: 0, deltaTime: deltaTime)
        }
        let interfaceOrientation = (UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
                                    as? UIWindowScene)?.interfaceOrientation ?? .portrait
        let orientation: ASCIIPoolMotion.Orientation
        switch interfaceOrientation {
        case .landscapeLeft: orientation = .interfaceLeft
        case .landscapeRight: orientation = .interfaceRight
        case .portraitUpsideDown: orientation = .upsideDown
        default: orientation = .portrait
        }
        let tilt = orientation.screenAxes(x: sample.gravity.x, y: sample.gravity.y)
        let movement = orientation.screenAxes(x: sample.userAcceleration.x, y: sample.userAcceleration.y)
        // Core Motion fuses the gyroscope and accelerometer. Gravity keeps the water
        // at the lowered edge; angular velocity gives a turn its immediate splash.
        return motionResponse.update(gravityX: tilt.x, gravityY: tilt.y,
                                     rotationRateZ: sample.rotationRate.z,
                                     accelerationX: movement.x, accelerationY: movement.y,
                                     deltaTime: deltaTime)
    }
}

private struct ASCIIPoolCanvas: View {
    let particles: [ASCIIPoolSimulation.Particle]
    let worldWidth: Double
    let particleRadius: Double
    let statusBarHeight: CGFloat
    private static let ramp = Array(" ·:-~=+*#%@")

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            let cell = 13.0
            let columns = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            guard columns > 0, rows > 0, worldWidth > 0 else { return }
            var counts = [Double](repeating: 0, count: columns * rows)
            var speeds = [Double](repeating: 0, count: columns * rows)
            var surface = [Int](repeating: rows, count: columns)
            // Reconstruct the particle's fluid footprint, rather than sampling only
            // its center. The web uses more physics particles; this retains its full
            // 13pt ASCII field within the native 600-particle simulation budget.
            let scale = size.height / 3
            let diameter = 2 * particleRadius * scale
            let radius = max(cell * 0.75, particleRadius * scale * 1.4)
            let expected = Double.pi * radius * radius / 2 / (sqrt(3) / 2 * diameter * diameter)
            for particle in particles {
                let x = particle.x / worldWidth * size.width
                let y = (1 - particle.y / 3) * size.height
                let minColumn = max(0, Int((x - radius) / cell))
                let maxColumn = min(columns - 1, Int((x + radius) / cell))
                let minRow = max(0, Int((y - radius) / cell))
                let maxRow = min(rows - 1, Int((y + radius) / cell))
                guard minColumn <= maxColumn, minRow <= maxRow else { continue }
                for row in minRow...maxRow {
                    for column in minColumn...maxColumn {
                        let dx = (Double(column) + 0.5) * cell - x
                        let dy = (Double(row) + 0.5) * cell - y
                        let weight = max(0, 1 - (dx * dx + dy * dy) / (radius * radius))
                        guard weight > 0.05 else { continue }
                        let index = row * columns + column
                        counts[index] += weight
                        speeds[index] += (abs(particle.velocityX) + abs(particle.velocityY)) * weight
                        surface[column] = min(surface[column], row)
                    }
                }
            }
            // Resolve each glyph once per frame; only density/speed picks which glyph
            // to draw. This is the web's ramp and its depth/surface weighting.
            let glyphs = Self.ramp.map {
                context.resolve(Text(String($0)).font(.custom("DepartureMono-Regular", fixedSize: 11))
                    .foregroundColor(.black))
            }
            for row in 0..<rows {
                for column in 0..<columns {
                    let index = row * columns + column
                    guard counts[index] > 0 else { continue }
                    let speed = speeds[index] / counts[index]
                    let depth = min(1, Double(row - surface[column]) / 16)
                    let jitter = Double(((column &* 73856093) ^ (row &* 19349663)) & 1023) / 1023 - 0.5
                    var weight = 0.1 + 0.4 * depth + 0.3 * min(speed / 1.4, 1.6)
                    weight += 0.08 * (counts[index] / expected - 1) + 0.16 * jitter
                    if surface[column] == row { weight += 0.3 }
                    let glyph = max(1, min(Self.ramp.count - 1, 1 + Int(weight * 9)))
                    // Inverted water can reach the top; keep the system clock legible.
                    let y = (Double(row) + 0.5) * cell
                    let statusFade = min(1, max(0, (y - statusBarHeight - cell / 2) / cell))
                    context.opacity = (0.62 + 0.38 * min(1, max(0, weight * 1.5))) * statusFade
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
            for y in stride(from: 2.0, to: top, by: 4) {
                var dots = Path()
                for x in stride(from: 2.0, to: size.width, by: 4) {
                    dots.addRect(CGRect(x: x, y: y, width: 1, height: 1))
                }
                context.fill(dots, with: .color(.black.opacity(0.08 * (1 - smoothstep(top - 160, top - 12, y)))))
            }
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
                    guard density >= 0.02 else { continue }
                    let i = Int(x / 3), j = Int(y / 3)
                    let threshold = (Double(bayer[(j & 3) * 4 + (i & 3)]) + 0.5) / 16 + (hash(i, j) - 0.5) * 0.3
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

    private func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt32(truncatingIfNeeded: x) &* 374761393 &+ UInt32(truncatingIfNeeded: y) &* 668265263
        h = (h ^ (h >> 13)) &* 1274126177
        return Double(h ^ (h >> 16)) / Double(UInt32.max)
    }
}
