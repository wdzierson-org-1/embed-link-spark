import XCTest
@testable import StashKit

final class ASCIIPoolMotionTests: XCTestCase {
    func testGravityPreservesDirectionIncludingInversionAndSideways() {
        let upright = settled(gravityX: 0, gravityY: -1)
        let inverted = settled(gravityX: 0, gravityY: 1)
        let sideways = settled(gravityX: 1, gravityY: 0)
        let diagonal = settled(gravityX: 0.4, gravityY: 0.3)

        XCTAssertLessThan(upright.y, -11.9)
        XCTAssertGreaterThan(inverted.y, 11.9, "Inverting the phone must spill toward the screen's top")
        XCTAssertEqual(inverted.x, 0, accuracy: 0.001)
        XCTAssertGreaterThan(sideways.x, 11.9)
        XCTAssertEqual(sideways.y, 0, accuracy: 0.001, "Sideways gravity must not retain an artificial downward pull")
        XCTAssertEqual(diagonal.x / diagonal.y, 4.0 / 3, accuracy: 0.001)
        XCTAssertGreaterThan(diagonal.y, 0)
    }

    func testInterfaceOrientationsMapBothScreenAxes() {
        let input = (x: 0.25, y: -0.75)
        let cases: [(ASCIIPoolMotion.Orientation, Double, Double)] = [
            (.portrait, 0.25, -0.75),
            (.interfaceLeft, -0.75, -0.25),
            (.interfaceRight, 0.75, 0.25),
            (.upsideDown, -0.25, 0.75),
        ]
        for (orientation, expectedX, expectedY) in cases {
            let screen = orientation.screenAxes(x: input.x, y: input.y)
            XCTAssertEqual(screen.x, expectedX)
            XCTAssertEqual(screen.y, expectedY)
            let force = settled(gravityX: screen.x, gravityY: screen.y)
            XCTAssertEqual(force.x, expectedX * 12, accuracy: 0.001)
            XCTAssertEqual(force.y, expectedY * 12, accuracy: 0.001)
        }
    }

    func testClockwiseAndCounterclockwiseRotationSplashInOppositeDirectionsWhileFlat() {
        let clockwise = settled(gravityX: 0, gravityY: 0, rotationRateZ: -2)
        let counterclockwise = settled(gravityX: 0, gravityY: 0, rotationRateZ: 2)
        XCTAssertGreaterThan(clockwise.x, 5, "Clockwise rotation has negative z rate and must push right")
        XCTAssertLessThan(counterclockwise.x, -5)
        XCTAssertEqual(clockwise.x, -counterclockwise.x, accuracy: 0.001)
        XCTAssertLessThan(clockwise.y, 0)
        XCTAssertGreaterThan(clockwise.y, -3, "A flat phone needs only a weak downward fallback")
    }

    func testGyroImpulseSettlesAfterRotationStops() {
        var motion = ASCIIPoolMotion()
        for _ in 0..<30 {
            motion.update(gravityX: 0, gravityY: 0, rotationRateZ: -2, deltaTime: 1.0 / 60)
        }
        XCTAssertGreaterThan(motion.force.x, 5)
        let peak = motion.force.x
        motion.update(gravityX: 0, gravityY: 0, rotationRateZ: 0, deltaTime: 1.0 / 60)
        XCTAssertGreaterThan(motion.force.x, 0, "Stopping should decay rather than snap")
        XCTAssertLessThan(motion.force.x, peak)
        for _ in 0..<120 {
            motion.update(gravityX: 0, gravityY: 0, rotationRateZ: 0, deltaTime: 1.0 / 60)
        }
        XCTAssertEqual(motion.force.x, 0, accuracy: 0.001)
        XCTAssertTrue((-3..<0).contains(motion.force.y))
    }

    func testOptionalAccelerationReinforcesBothScreenDirections() {
        var motion = ASCIIPoolMotion()
        for _ in 0..<120 {
            motion.update(gravityX: 0, gravityY: -1, rotationRateZ: 0,
                          accelerationX: -0.5, accelerationY: 1, deltaTime: 1.0 / 60)
        }
        XCTAssertLessThan(motion.force.x, -5)
        XCTAssertGreaterThan(motion.force.y, 0)
    }

    func testSmoothingIsGradualAndIndependentOfFrameRate() {
        var firstFrame = ASCIIPoolMotion()
        let force = firstFrame.update(gravityX: 1, gravityY: 0, rotationRateZ: 0, deltaTime: 1.0 / 60)
        XCTAssertGreaterThan(force.x, 0)
        XCTAssertLessThan(force.x, 12, "One frame must not jump to the target")

        func response(hz: Int) -> ASCIIPoolMotion.Vector {
            var motion = ASCIIPoolMotion()
            for direction in [1.0, -1.0] {
                for _ in 0..<(hz / 5) {
                    motion.update(gravityX: direction * 0.6, gravityY: 0.8,
                                  rotationRateZ: -direction, deltaTime: 1.0 / Double(hz))
                }
            }
            return motion.force
        }
        let slow = response(hz: 30)
        let fast = response(hz: 120)
        XCTAssertEqual(slow.x, fast.x, accuracy: 1e-10)
        XCTAssertEqual(slow.y, fast.y, accuracy: 1e-10)
    }

    func testExtremeAndNonfiniteSamplesStayBoundedAndRecover() {
        var motion = ASCIIPoolMotion()
        for value in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude, -.greatestFiniteMagnitude] {
            for _ in 0..<30 {
                let force = motion.update(gravityX: value, gravityY: value, rotationRateZ: value,
                                          accelerationX: value, accelerationY: value, deltaTime: 4)
                XCTAssertTrue(force.x.isFinite && force.y.isFinite)
                XCTAssertLessThanOrEqual(hypot(force.x, force.y), 30.000001)
            }
        }
        for _ in 0..<120 {
            motion.update(gravityX: 0, gravityY: 1, rotationRateZ: 0, deltaTime: 1.0 / 60)
        }
        XCTAssertEqual(motion.force.x, 0, accuracy: 0.001)
        XCTAssertEqual(motion.force.y, 12, accuracy: 0.001)
    }

    func testInvalidOrZeroElapsedTimeDoesNotChangeForce() {
        var motion = ASCIIPoolMotion()
        let original = motion.force
        for deltaTime in [Double.nan, .infinity, -.infinity, -1, 0] {
            let actual = motion.update(gravityX: 1, gravityY: 1, rotationRateZ: -2, deltaTime: deltaTime)
            XCTAssertEqual(actual, original)
        }
    }

    func testFlatGyroRotationsMoveActualLiquidInOppositeDirections() {
        var clockwise = ASCIIPoolSimulation(width: 1.4, maxParticles: 600)
        var counterclockwise = clockwise
        var clockwiseMotion = ASCIIPoolMotion()
        var counterclockwiseMotion = ASCIIPoolMotion()
        for _ in 0..<60 {
            let right = clockwiseMotion.update(gravityX: 0, gravityY: 0, rotationRateZ: -2, deltaTime: 1.0 / 60)
            let left = counterclockwiseMotion.update(gravityX: 0, gravityY: 0, rotationRateZ: 2, deltaTime: 1.0 / 60)
            clockwise.step(deltaTime: 1.0 / 60, gravityX: right.x, gravityY: right.y)
            counterclockwise.step(deltaTime: 1.0 / 60, gravityX: left.x, gravityY: left.y)
        }
        let rightMean = clockwise.particles.map(\.x).reduce(0, +) / Double(clockwise.particles.count)
        let leftMean = counterclockwise.particles.map(\.x).reduce(0, +) / Double(counterclockwise.particles.count)
        XCTAssertGreaterThan(rightMean, leftMean + 0.1,
                             "Opposite gyro samples must move the actual pool, not only change the force vector")
        assertContained(clockwise)
        assertContained(counterclockwise)
    }

    func testInvertedGravityRaisesActualLiquidWhileKeepingItContained() {
        var inverted = ASCIIPoolSimulation(width: 1.4, maxParticles: 600)
        var upright = inverted
        var invertedMotion = ASCIIPoolMotion()
        var uprightMotion = ASCIIPoolMotion()
        for _ in 0..<120 {
            let up = invertedMotion.update(gravityX: 0, gravityY: 1, rotationRateZ: 0, deltaTime: 1.0 / 60)
            let down = uprightMotion.update(gravityX: 0, gravityY: -1, rotationRateZ: 0, deltaTime: 1.0 / 60)
            inverted.step(deltaTime: 1.0 / 60, gravityX: up.x, gravityY: up.y)
            upright.step(deltaTime: 1.0 / 60, gravityX: down.x, gravityY: down.y)
        }
        let invertedMean = inverted.particles.map(\.y).reduce(0, +) / Double(inverted.particles.count)
        let uprightMean = upright.particles.map(\.y).reduce(0, +) / Double(upright.particles.count)
        XCTAssertGreaterThan(invertedMean, uprightMean + 0.5,
                             "Inversion must move the actual fluid toward the top of the y-up world")
        assertContained(inverted)
        assertContained(upright)
    }

    private func assertContained(_ pool: ASCIIPoolSimulation, file: StaticString = #filePath, line: UInt = #line) {
        for particle in pool.particles {
            XCTAssertTrue(particle.x.isFinite && particle.y.isFinite &&
                          particle.velocityX.isFinite && particle.velocityY.isFinite, file: file, line: line)
            XCTAssertTrue((0...pool.width).contains(particle.x) && (0...pool.height).contains(particle.y),
                          file: file, line: line)
        }
    }

    private func settled(gravityX: Double, gravityY: Double, rotationRateZ: Double = 0) -> ASCIIPoolMotion.Vector {
        var motion = ASCIIPoolMotion()
        for _ in 0..<120 {
            motion.update(gravityX: gravityX, gravityY: gravityY, rotationRateZ: rotationRateZ, deltaTime: 1.0 / 60)
        }
        return motion.force
    }
}
