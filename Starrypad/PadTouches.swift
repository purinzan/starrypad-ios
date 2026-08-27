import SwiftUI
import UIKit

/// Raw multitouch over the pad grid.
///
/// SwiftUI gestures are the wrong tool here. A DragGesture per pad serialises:
/// a second finger landing on another pad while the first is still down mostly
/// does not arrive, which on a drum machine means you cannot play two pads at
/// once - the one thing a pad grid exists for. UIKit hands over every touch,
/// so the grid takes one view and does its own hit testing.
///
/// The maths matching a point to a pad is the same as before, and the same as
/// the tests cover: four columns across, four rows down, and the top row of the
/// screen is the last four positions because pad 0 is bottom left.
struct PadTouches: UIViewRepresentable {

    /// A touch landing: which position, and how far up the pad it hit.
    var onDown: (Int, Int, Double) -> Void          // id, position, depth 0...1
    var onMove: (Int, Int?) -> Void                 // id, position under it now
    var onUp: (Int) -> Void

    func makeUIView(context: Context) -> TouchView {
        let view = TouchView()
        view.isMultipleTouchEnabled = true
        view.backgroundColor = .clear
        view.onDown = onDown
        view.onMove = onMove
        view.onUp = onUp
        return view
    }

    func updateUIView(_ view: TouchView, context: Context) {
        view.onDown = onDown
        view.onMove = onMove
        view.onUp = onUp
    }

    final class TouchView: UIView {
        var onDown: ((Int, Int, Double) -> Void)?
        var onMove: ((Int, Int?) -> Void)?
        var onUp: ((Int) -> Void)?

        /// UITouch objects are reused, so they are identified by address for
        /// as long as they are down and never held on to afterwards.
        private var ids: [ObjectIdentifier: Int] = [:]
        private var nextID = 0

        private func cell(at point: CGPoint) -> (position: Int, depth: Double)? {
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            let cellWidth = bounds.width / 4, cellHeight = bounds.height / 4
            let column = Int(point.x / cellWidth), row = Int(point.y / cellHeight)
            guard (0..<4).contains(column), (0..<4).contains(row) else { return nil }
            // Higher up the pad is a harder hit, when there is no force to read.
            let within = (point.y - CGFloat(row) * cellHeight) / cellHeight
            return ((3 - row) * 4 + column, 1.0 - Double(min(max(within, 0), 1)))
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let hit = cell(at: touch.location(in: self)) else { continue }
                nextID &+= 1
                ids[ObjectIdentifier(touch)] = nextID
                onDown?(nextID, hit.position, hit.depth)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let id = ids[ObjectIdentifier(touch)] else { continue }
                onMove?(id, cell(at: touch.location(in: self))?.position)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish(touches)
        }

        private func finish(_ touches: Set<UITouch>) {
            for touch in touches {
                guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
                onUp?(id)
            }
        }
    }
}
