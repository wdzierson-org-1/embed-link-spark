import XCTest
@testable import StashKit

final class ASCIIPoolSimulationTests: XCTestCase {
    func testStartsAsBoundedShallowPoolWithinParticleBudget() {
        let pool = ASCIIPoolSimulation(width: 1.4, height: 3, maxParticles: 1_600)
        XCTAssertGreaterThan(pool.particles.count, 200)
        XCTAssertLessThanOrEqual(pool.particles.count, 1_600)
        assertBounded(pool)
        XCTAssertLessThan(pool.particles.map(\.y).max() ?? 3, 1.1)
    }

    func testHorizontalGravityMovesWaterInItsDirection() {
        var right = ASCIIPoolSimulation(width: 1.4)
        var left = right
        for _ in 0..<30 {
            right.step(deltaTime: 1 / 30, gravityX: 5, gravityY: -9.81)
            left.step(deltaTime: 1 / 30, gravityX: -5, gravityY: -9.81)
        }
        XCTAssertGreaterThan(meanX(right), meanX(left) + 0.1)
        assertBounded(right)
        assertBounded(left)
    }

    func testReturnsToCalmAfterTiltStops() {
        var pool = ASCIIPoolSimulation(width: 1.4)
        for _ in 0..<30 { pool.step(deltaTime: 1 / 30, gravityX: 6, gravityY: -9.81) }
        for _ in 0..<300 { pool.step(deltaTime: 1 / 30, gravityX: 0, gravityY: -9.81) }
        assertBounded(pool)
        let speed = pool.particles.reduce(0) { $0 + hypot($1.velocityX, $1.velocityY) } / Double(pool.particles.count)
        XCTAssertLessThan(speed, 0.3, "A resting tank must lose its slosh energy")
        XCTAssertLessThan(abs(meanX(pool) - pool.width / 2), 0.1)
    }

    func testExtremeForcesAndLongFrameRemainFiniteAndContained() {
        var pool = ASCIIPoolSimulation(width: 1.4)
        for i in 0..<60 {
            pool.step(deltaTime: 4, gravityX: i.isMultiple(of: 2) ? 1e12 : -1e12, gravityY: 1e12)
        }
        pool.step(deltaTime: .infinity, gravityX: .nan, gravityY: .infinity)
        pool.step(deltaTime: -.infinity, gravityX: .infinity, gravityY: .nan)
        assertBounded(pool)
    }

    func testPerformanceOf300MobileFrames() {
        var pool = ASCIIPoolSimulation(width: 1.4)
        let start = Date.timeIntervalSinceReferenceDate
        for frame in 0..<300 {
            pool.step(deltaTime: 1 / 30, gravityX: sin(Double(frame) / 30) * 3, gravityY: -9.81)
        }
        let milliseconds = (Date.timeIntervalSinceReferenceDate - start) * 1_000 / 300
        print("ASCII_POOL_PERF particles=\(pool.particles.count) milliseconds_per_frame=\(milliseconds)")
        assertBounded(pool)
    }

    private func meanX(_ pool: ASCIIPoolSimulation) -> Double {
        pool.particles.reduce(0) { $0 + $1.x } / Double(pool.particles.count)
    }

    private func assertBounded(_ pool: ASCIIPoolSimulation, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(pool.particles.isEmpty, file: file, line: line)
        for p in pool.particles {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite && p.velocityX.isFinite && p.velocityY.isFinite, file: file, line: line)
            XCTAssertTrue((0...pool.width).contains(p.x) && (0...pool.height).contains(p.y), file: file, line: line)
        }
    }
}
