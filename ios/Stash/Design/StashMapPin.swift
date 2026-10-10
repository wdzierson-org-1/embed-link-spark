import SwiftUI

/// The web's Lucide MapPin outline, shared by capture controls and saved place labels.
struct StashMapPin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 20, y: 10))
        path.addCurve(to: CGPoint(x: 12, y: 22), control1: CGPoint(x: 20, y: 15), control2: CGPoint(x: 12, y: 22))
        path.addCurve(to: CGPoint(x: 4, y: 10), control1: CGPoint(x: 12, y: 22), control2: CGPoint(x: 4, y: 15))
        path.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 4, y: 5.58), control2: CGPoint(x: 7.58, y: 2))
        path.addCurve(to: CGPoint(x: 20, y: 10), control1: CGPoint(x: 16.42, y: 2), control2: CGPoint(x: 20, y: 5.58))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: 9, y: 7, width: 6, height: 6))
        return path.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
