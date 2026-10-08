import Foundation

/// Converts screen-aligned motion samples into forces for the pool's y-up world.
/// Keeps sensor collection outside StashKit; retain one value across animation frames.
public struct ASCIIPoolMotion: Sendable {
    public struct Vector: Equatable, Sendable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    /// Interface orientations, whose landscape names differ from device orientation.
    public enum Orientation: Sendable {
        case portrait, interfaceLeft, interfaceRight, upsideDown

        /// Rotate device x/y samples to the interface's right/up axes. Apply to both
        /// gravity and user acceleration. The z rotation rate needs no in-plane remap.
        public func screenAxes(x: Double, y: Double) -> Vector {
            let x = x.isFinite ? x : 0
            let y = y.isFinite ? y : 0
            switch self {
            case .portrait: return Vector(x: x, y: y)
            case .interfaceLeft: return Vector(x: y, y: -x)
            case .interfaceRight: return Vector(x: -y, y: x)
            case .upsideDown: return Vector(x: -x, y: -y)
            }
        }
    }

    public private(set) var force = Vector(x: 0, y: -9.81)

    public init() {}

    /// Gravity and acceleration are in g; rotation is radians/second, positive CCW.
    /// A clockwise turn therefore contributes a rightward splash. Angular force
    /// decays with the filter after rotation stops; it never accumulates in state.
    /// The vector magnitude is capped at 30, matching the simulation's force budget.
    @discardableResult
    public mutating func update(gravityX: Double, gravityY: Double, rotationRateZ: Double,
                                accelerationX: Double = 0, accelerationY: Double = 0,
                                deltaTime: Double) -> Vector {
        guard deltaTime.isFinite, deltaTime > 0 else { return force }

        let gx = Self.finiteClamp(gravityX, limit: 1)
        let gy = Self.finiteClamp(gravityY, limit: 1)
        let ax = Self.finiteClamp(accelerationX, limit: 3)
        let ay = Self.finiteClamp(accelerationY, limit: 3)
        let spin = Self.finiteClamp(rotationRateZ, limit: 6)

        // A flat phone has little in-plane gravity. Fade a weak downward pull in
        // only there; sideways and inverted phones retain their full gravity vector.
        let flatPull = 2 * max(0, 1 - hypot(gx, gy) / 0.2)
        var targetX = gx * 12 + ax * 18 - spin * 5
        var targetY = gy * 12 + ay * 18 - flatPull
        let magnitude = hypot(targetX, targetY)
        if magnitude > 30 {
            targetX *= 30 / magnitude
            targetY *= 30 / magnitude
        }

        // Exponential smoothing depends on elapsed time, not callback frequency.
        // Bound catch-up after suspension; invalid time leaves the last force intact.
        let blend = 1 - exp(-min(deltaTime, 0.25) * 9)
        force = Vector(x: force.x + (targetX - force.x) * blend,
                       y: force.y + (targetY - force.y) * blend)
        return force
    }

    private static func finiteClamp(_ value: Double, limit: Double) -> Double {
        value.isFinite ? min(limit, max(-limit, value)) : 0
    }
}
