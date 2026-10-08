import Foundation

/// The marketing header's particle/MAC-grid FLIP pool, bounded for native animation.
/// Ported from `docs/superpowers/prototypes/2026-10-06-stashe-homepage/js/liquid.js`.
/// The world is y-up, origin bottom-left. Draw at `(x / width, 1 - y / height)`.
/// Sensor collection and drawing stay outside this value type. No saved content is involved.
public struct ASCIIPoolSimulation: Sendable {
    public struct Particle: Sendable {
        public let x: Double
        public let y: Double
        public let velocityX: Double
        public let velocityY: Double
    }
    public let width: Double
    public let height: Double
    public let particleRadius: Double
    public var particles: [Particle] {
        (0..<count).map { Particle(x: position[2 * $0], y: position[2 * $0 + 1],
                                 velocityX: velocity[2 * $0], velocityY: velocity[2 * $0 + 1]) }
    }

    private let nx: Int, ny: Int, h: Double, count: Int
    private let hashNX: Int, hashNY: Int, inverseHashSpacing: Double
    private var position: [Double], velocity: [Double]
    private var u: [Double], v: [Double], oldU: [Double], oldV: [Double]
    private var weightU: [Double], weightV: [Double], density: [Double]
    private var solid: [Double], kind: [Int]
    private var restDensity = 0.0
    private var hashCount: [Int], hashStart: [Int], hashIDs: [Int]
    private static let fluid = 0, air = 1, wall = 2

    /// 35% fill, the web's mobile resolution, and a hard 2,000-particle ceiling.
    /// Invalid/degenerate dimensions use a useful default rather than allocating unbounded grids.
    public init(width: Double, height: Double = 3, maxParticles: Int = 2_000) {
        let width = width.isFinite ? min(12, max(0.5, width)) : 1.4
        let height = height.isFinite ? min(12, max(0.5, height)) : 3
        self.width = width; self.height = height
        let budget = min(2_000, max(32, maxParticles))
        var spacing = min(width / 8, height / 56)
        var cellsX = 0, cellsY = 0, actualSpacing = 0.0, particlesX = 0, particlesY = 0
        repeat {
            cellsX = max(4, Int(width / spacing) + 1)
            cellsY = max(4, Int(height / spacing) + 1)
            actualSpacing = max(width / Double(cellsX), height / Double(cellsY))
            let diameter = 0.6 * actualSpacing
            particlesX = max(1, Int((width - 2.6 * actualSpacing) / diameter))
            particlesY = max(1, Int((0.35 * height - 2.6 * actualSpacing) / (sqrt(3) / 2 * diameter)))
            spacing *= 1.06
        } while particlesX * particlesY > budget
        nx = cellsX; ny = cellsY; h = actualSpacing
        particleRadius = 0.3 * actualSpacing
        count = particlesX * particlesY
        position = Array(repeating: 0, count: count * 2)
        velocity = position
        let diameter = 2 * particleRadius
        for i in 0..<particlesX {
            for j in 0..<particlesY {
                let k = 2 * (i * particlesY + j)
                position[k] = h + particleRadius + diameter * Double(i) + (j.isMultiple(of: 2) ? 0 : particleRadius)
                position[k + 1] = h + particleRadius + sqrt(3) / 2 * diameter * Double(j)
            }
        }
        let cells = nx * ny
        u = Array(repeating: 0, count: cells); v = u; oldU = u; oldV = u
        weightU = u; weightV = u; density = u
        solid = Array(repeating: 1, count: cells)
        kind = Array(repeating: Self.air, count: cells)
        for i in 0..<nx {
            for j in 0..<ny where i == 0 || i == nx - 1 || j == 0 {
                solid[i * ny + j] = 0
            }
        }
        inverseHashSpacing = 1 / (2.2 * particleRadius)
        hashNX = Int(width * inverseHashSpacing) + 1
        hashNY = Int(height * inverseHashSpacing) + 1
        hashCount = Array(repeating: 0, count: hashNX * hashNY)
        hashStart = Array(repeating: 0, count: hashNX * hashNY + 1)
        hashIDs = Array(repeating: 0, count: count)
        containParticles()
    }

    /// Bounds catch-up to 1/15 s and integrates in small substeps, at the source's 80% speed.
    /// Nonfinite samples are ignored; extreme sensor spikes cannot destabilize the tank.
    public mutating func step(deltaTime: Double, gravityX: Double = 0, gravityY: Double = -9.81) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let gx = gravityX.isFinite ? Self.clamp(gravityX, -30, 30) : 0
        let gy = gravityY.isFinite ? Self.clamp(gravityY, -30, 30) : -9.81
        let duration = min(deltaTime, 1 / 15) * 0.8
        let steps = max(1, Int(ceil(duration / (1 / 60))))
        let dt = duration / Double(steps)
        for _ in 0..<steps {
            for i in 0..<count {
                velocity[2 * i] += dt * gx
                velocity[2 * i + 1] += dt * gy
                position[2 * i] += dt * velocity[2 * i]
                position[2 * i + 1] += dt * velocity[2 * i + 1]
            }
            separateParticles()
            containParticles()
            transferToGrid()
            updateDensity()
            solvePressure()
            transferToParticles()
            // Projection changes velocities after collision; bound these too before next frame.
            containParticles()
        }
    }

    private static func clamp(_ x: Double, _ low: Double, _ high: Double) -> Double {
        min(high, max(low, x))
    }

    private mutating func containParticles() {
        let minX = h + particleRadius, maxX = min(width - particleRadius, Double(nx - 1) * h - particleRadius)
        let minY = h + particleRadius, maxY = min(height - particleRadius, Double(ny - 1) * h - particleRadius)
        for i in 0..<count {
            let x = 2 * i, y = x + 1
            if position[x] < minX { position[x] = minX; velocity[x] = max(0, velocity[x]) }
            if position[x] > maxX { position[x] = maxX; velocity[x] = min(0, velocity[x]) }
            if position[y] < minY { position[y] = minY; velocity[y] = max(0, velocity[y]) }
            if position[y] > maxY { position[y] = maxY; velocity[y] = min(0, velocity[y]) }
            velocity[x] = Self.clamp(velocity[x], -12, 12)
            velocity[y] = Self.clamp(velocity[y], -12, 12)
        }
    }

    /// Spatial hashing keeps two separation passes linear in particle count.
    private mutating func separateParticles() {
        for i in hashCount.indices { hashCount[i] = 0 }
        for i in 0..<count { hashCount[hashCell(position[2 * i], position[2 * i + 1])] += 1 }
        var total = 0
        for i in hashCount.indices { total += hashCount[i]; hashStart[i] = total }
        hashStart[hashCount.count] = total
        for i in 0..<count {
            let cell = hashCell(position[2 * i], position[2 * i + 1])
            hashStart[cell] -= 1
            hashIDs[hashStart[cell]] = i
        }
        let distance = 2 * particleRadius, distanceSquared = distance * distance
        for _ in 0..<2 {
            for i in 0..<count {
                let px = position[2 * i], py = position[2 * i + 1]
                let cx = min(hashNX - 1, max(0, Int(px * inverseHashSpacing)))
                let cy = min(hashNY - 1, max(0, Int(py * inverseHashSpacing)))
                for x in max(0, cx - 1)...min(hashNX - 1, cx + 1) {
                    for y in max(0, cy - 1)...min(hashNY - 1, cy + 1) {
                        let cell = x * hashNY + y
                        for slot in hashStart[cell]..<hashStart[cell + 1] {
                            let other = hashIDs[slot]
                            if other == i { continue }
                            let dx = position[2 * other] - px, dy = position[2 * other + 1] - py
                            let squared = dx * dx + dy * dy
                            if squared == 0 || squared >= distanceSquared { continue }
                            let length = sqrt(squared)
                            let correction = 0.5 * (distance - length) / length
                            position[2 * i] -= dx * correction; position[2 * i + 1] -= dy * correction
                            position[2 * other] += dx * correction; position[2 * other + 1] += dy * correction
                        }
                    }
                }
            }
        }
    }

    private func hashCell(_ x: Double, _ y: Double) -> Int {
        let cx = min(hashNX - 1, max(0, Int(x * inverseHashSpacing)))
        let cy = min(hashNY - 1, max(0, Int(y * inverseHashSpacing)))
        return cx * hashNY + cy
    }

    /// Four MAC-grid neighbours and bilinear weights, with half-cell component offsets.
    private func stencil(_ x: Double, _ y: Double, dx: Double, dy: Double)
        -> (a: Int, b: Int, c: Int, d: Int, wa: Double, wb: Double, wc: Double, wd: Double) {
        let x = Self.clamp(x, h, Double(nx - 1) * h)
        let y = Self.clamp(y, h, Double(ny - 1) * h)
        let ix = min(nx - 2, max(0, Int((x - dx) / h)))
        let iy = min(ny - 2, max(0, Int((y - dy) / h)))
        let tx = Self.clamp((x - dx - Double(ix) * h) / h, 0, 1)
        let ty = Self.clamp((y - dy - Double(iy) * h) / h, 0, 1)
        return (ix * ny + iy, (ix + 1) * ny + iy, (ix + 1) * ny + iy + 1, ix * ny + iy + 1,
                (1 - tx) * (1 - ty), tx * (1 - ty), tx * ty, (1 - tx) * ty)
    }

    private mutating func transferToGrid() {
        oldU = u; oldV = v
        for i in u.indices {
            u[i] = 0; v[i] = 0; weightU[i] = 0; weightV[i] = 0
            kind[i] = solid[i] == 0 ? Self.wall : Self.air
        }
        for i in 0..<count {
            let x = position[2 * i], y = position[2 * i + 1]
            let cell = min(nx - 1, max(0, Int(x / h))) * ny + min(ny - 1, max(0, Int(y / h)))
            if kind[cell] == Self.air { kind[cell] = Self.fluid }
            let s = stencil(x, y, dx: 0, dy: h / 2), vx = velocity[2 * i]
            u[s.a] += vx * s.wa; u[s.b] += vx * s.wb; u[s.c] += vx * s.wc; u[s.d] += vx * s.wd
            weightU[s.a] += s.wa; weightU[s.b] += s.wb; weightU[s.c] += s.wc; weightU[s.d] += s.wd
            let t = stencil(x, y, dx: h / 2, dy: 0), vy = velocity[2 * i + 1]
            v[t.a] += vy * t.wa; v[t.b] += vy * t.wb; v[t.c] += vy * t.wc; v[t.d] += vy * t.wd
            weightV[t.a] += t.wa; weightV[t.b] += t.wb; weightV[t.c] += t.wc; weightV[t.d] += t.wd
        }
        for i in u.indices {
            if weightU[i] > 0 { u[i] /= weightU[i] }
            if weightV[i] > 0 { v[i] /= weightV[i] }
        }
        for x in 0..<nx {
            for y in 0..<ny {
                let i = x * ny + y
                if kind[i] == Self.wall || (x > 0 && kind[i - ny] == Self.wall) { u[i] = oldU[i] }
                if kind[i] == Self.wall || (y > 0 && kind[i - 1] == Self.wall) { v[i] = oldV[i] }
            }
        }
    }

    private mutating func updateDensity() {
        for i in density.indices { density[i] = 0 }
        for i in 0..<count {
            let s = stencil(position[2 * i], position[2 * i + 1], dx: h / 2, dy: h / 2)
            density[s.a] += s.wa; density[s.b] += s.wb; density[s.c] += s.wc; density[s.d] += s.wd
        }
        if restDensity == 0 {
            var sum = 0.0, cells = 0
            for i in kind.indices where kind[i] == Self.fluid { sum += density[i]; cells += 1 }
            if cells > 0 { restDensity = sum / Double(cells) }
        }
    }

    /// Incompressibility projection. 24 passes trades the web's 40 for a bounded mobile budget.
    private mutating func solvePressure() {
        oldU = u; oldV = v
        for _ in 0..<24 {
            for x in 1..<(nx - 1) {
                for y in 1..<(ny - 1) {
                    let i = x * ny + y
                    if kind[i] != Self.fluid { continue }
                    let left = i - ny, right = i + ny, bottom = i - 1, top = i + 1
                    let sum = solid[left] + solid[right] + solid[bottom] + solid[top]
                    if sum == 0 { continue }
                    var divergence = u[right] - u[i] + v[top] - v[i]
                    if restDensity > 0 { divergence -= max(0, density[i] - restDensity) }
                    let pressure = -divergence / sum * 1.9
                    u[i] -= solid[left] * pressure; u[right] += solid[right] * pressure
                    v[i] -= solid[bottom] * pressure; v[top] += solid[top] * pressure
                }
            }
        }
    }

    private mutating func transferToParticles() {
        for i in 0..<count {
            velocity[2 * i] = interpolatedVelocity(position[2 * i], position[2 * i + 1], horizontal: true, previous: velocity[2 * i])
            velocity[2 * i + 1] = interpolatedVelocity(position[2 * i], position[2 * i + 1], horizontal: false, previous: velocity[2 * i + 1])
        }
    }

    private func interpolatedVelocity(_ x: Double, _ y: Double, horizontal: Bool, previous: Double) -> Double {
        let s = stencil(x, y, dx: horizontal ? 0 : h / 2, dy: horizontal ? h / 2 : 0)
        let offset = horizontal ? ny : 1
        func valid(_ i: Int) -> Double { kind[i] != Self.air || (i >= offset && kind[i - offset] != Self.air) ? 1 : 0 }
        let a = s.wa * valid(s.a), b = s.wb * valid(s.b), c = s.wc * valid(s.c), d = s.wd * valid(s.d)
        let sum = a + b + c + d
        if sum == 0 { return previous }
        let field = horizontal ? u : v, old = horizontal ? oldU : oldV
        let pic = (a * field[s.a] + b * field[s.b] + c * field[s.c] + d * field[s.d]) / sum
        let correction = (a * (field[s.a] - old[s.a]) + b * (field[s.b] - old[s.b])
                          + c * (field[s.c] - old[s.c]) + d * (field[s.d] - old[s.d])) / sum
        return 0.14 * pic + 0.86 * (previous + correction)
    }
}
