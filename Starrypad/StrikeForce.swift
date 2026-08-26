import CoreMotion
import Foundation

/// How hard the phone was hit, from the knock it takes.
///
/// The obvious route is touch pressure, and it is not available: 3D Touch was
/// dropped from the iPhone years ago, so UITouch.force reads zero on anything
/// current. What a strike does leave is a jolt the accelerometer can see.
///
/// The jolt lands at the same instant as the touch, so the reading comes from a
/// buffer of what just happened rather than from waiting to see what happens
/// next - waiting would put back the delay that firing on touch-down removed.
///
/// The scale is learned rather than assumed. A finger on glass is a far smaller
/// event than the fixed range in the first version of this file expected, and
/// how small depends on the phone, the case, and whether it is in your hand or
/// flat on a table. Guessing that range once, wrongly, is what made every hit
/// fall through to the old position based velocity.
final class StrikeForce: ObservableObject {

    @Published private(set) var available = false
    /// The last reading and what it became, so the scale can be watched while
    /// playing instead of taken on trust.
    @Published private(set) var lastPeak: Double = 0
    @Published private(set) var lastVelocity: Int = 0
    /// The loudest hit seen lately, which is what full velocity is measured
    /// against.
    @Published private(set) var ceiling: Double = 0.12

    private let motion = CMMotionManager()
    private var samples: [(time: TimeInterval, magnitude: Double)] = []
    private let lock = NSLock()

    /// Sensor noise, not a hit. Measured on the device: the softest real hit
    /// read 0.0097 g, so this sits just under it.
    private let floor = 0.008
    private let ceilingFloor = 0.05
    private let ceilingLimit = 3.0
    /// The ceiling comes down as you play softer, so one heavy hit does not
    /// leave everything after it quiet.
    private let decay = 0.99

    func start() {
        guard !available else { return }
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 100
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                // userAcceleration already has gravity taken out, which raw
                // accelerometer readings do not.
                let a = data.userAcceleration
                self.record(data.timestamp, sqrt(a.x * a.x + a.y * a.y + a.z * a.z))
            }
            available = true
        } else if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = 1.0 / 100
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                let a = data.acceleration
                self.record(data.timestamp, abs(sqrt(a.x * a.x + a.y * a.y + a.z * a.z) - 1.0))
            }
            available = true
        }
        print("strike force: \(available ? "on" : "no motion sensor")")
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        motion.stopAccelerometerUpdates()
        available = false
    }

    private func record(_ time: TimeInterval, _ magnitude: Double) {
        lock.lock()
        samples.append((time, magnitude))
        if samples.count > 64 { samples.removeFirst(samples.count - 64) }
        lock.unlock()
    }

    private func peak(within seconds: TimeInterval = 0.07) -> Double {
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

        // Learn the range from what is actually being played. A hit louder than
        // anything so far becomes the new top; otherwise the top sinks slowly
        // back towards it.
        var top = max(ceilingFloor, min(ceilingLimit, ceiling * decay))
        if measured > top { top = min(ceilingLimit, measured) }

        let result: Int?
        if measured <= floor {
            result = nil
        } else {
            // Logarithmic, because the readings span more than a decade: 138
            // hits captured on the device ran from 0.0097 g to 0.36 g, with a
            // median of 0.017. Scaling that linearly puts an ordinary hit two
            // percent up the range and makes the whole instrument quiet; on a
            // log scale the same hit lands where it belongs. Loudness is heard
            // logarithmically anyway.
            let span = log(max(top, floor * 2) / floor)
            let scaled = min(1.0, log(measured / floor) / span)
            result = max(1, min(127, Int(24 + pow(scaled, 1.15) * 103)))
        }
        print(String(format: "strike %.4f g, ceiling %.3f -> %@",
                     measured, top, result.map(String.init) ?? "below floor"))
        DispatchQueue.main.async {
            self.lastPeak = measured
            self.ceiling = top
            self.lastVelocity = result ?? 0
        }
        return result
    }
}
