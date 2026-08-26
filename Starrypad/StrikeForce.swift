import CoreMotion
import Foundation

/// How hard the phone was hit, from the knock it takes.
///
/// The obvious route is touch pressure, and it is not available: 3D Touch was
/// dropped from the iPhone years ago, so UITouch.force reads zero on anything
/// current. What a strike does leave is a jolt in the accelerometer, and that
/// is a real measurement of force rather than a stand-in for it.
///
/// The jolt lands at the same instant as the touch, so the reading has to come
/// from a buffer of what just happened rather than from waiting to see what
/// happens next - waiting would put the delay back that touch-down removed.
final class StrikeForce: ObservableObject {

    /// Whether motion is there to read. False in the simulator, and on a
    /// device that refuses the sensor.
    @Published private(set) var available = false
    /// The last reading, so the calibration can be watched while playing.
    @Published private(set) var lastPeak: Double = 0

    private let motion = CMMotionManager()
    private var samples: [(time: TimeInterval, magnitude: Double)] = []
    private let lock = NSLock()

    /// Nothing below this is a hit; the phone is never perfectly still.
    var floor: Double = 0.06
    /// Where the scale tops out. A firm strike, not the hardest possible one,
    /// so normal playing reaches full velocity without needing violence.
    var ceiling: Double = 1.4

    func start() {
        guard motion.isAccelerometerAvailable else { return }
        motion.accelerometerUpdateInterval = 1.0 / 100
        motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            // Gravity is a constant offset on one axis; what a strike adds is
            // the departure from 1g in any direction.
            let raw = data.acceleration
            let magnitude = abs(sqrt(raw.x * raw.x + raw.y * raw.y + raw.z * raw.z) - 1.0)
            self.lock.lock()
            self.samples.append((data.timestamp, magnitude))
            if self.samples.count > 64 { self.samples.removeFirst(self.samples.count - 64) }
            self.lock.unlock()
        }
        available = true
    }

    func stop() {
        motion.stopAccelerometerUpdates()
        available = false
    }

    /// The strongest jolt in the last moments, which is the one you just made.
    func peak(within seconds: TimeInterval = 0.07) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let newest = samples.last?.time else { return 0 }
        return samples.reduce(0.0) { best, sample in
            sample.time >= newest - seconds ? max(best, sample.magnitude) : best
        }
    }

    /// A velocity from that jolt, or nil when there is nothing to read.
    func velocity() -> Int? {
        guard available else { return nil }
        let measured = peak()
        DispatchQueue.main.async { self.lastPeak = measured }
        guard measured > floor else { return nil }
        let span = max(0.0001, ceiling - floor)
        let scaled = min(1.0, (measured - floor) / span)
        // The curve is deliberate: linear force feels top heavy, because the
        // difference between a tap and a firm hit matters more than the
        // difference between firm and very firm.
        return max(1, min(127, Int(24 + pow(scaled, 0.7) * 103)))
    }
}
