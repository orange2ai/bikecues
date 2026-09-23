import Foundation
import CoreMotion

/// 计步器速度源：GPS 被挡住时（室内、隧道）的运动协处理器兜底。
/// Keep 们室内也有速度靠的就是它——加速度计能感知手机在动，GPS 不能。
final class PedometerSource {
    private let pedometer = CMPedometer()
    private var lastDistance: Double?
    private var lastTime: Date?

    /// 每次更新回调（主线程）：估算速度 km/h，无效时给 0
    var onSpeed: ((Double) -> Void)?

    func start() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        lastDistance = nil
        lastTime = nil
        // 首次调用系统会弹"运动与健身"授权
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            guard let self, let data, error == nil else { return }

            var kmh = 0.0
            if let d = data.distance?.doubleValue,
                      let prev = self.lastDistance, let prevTime = self.lastTime {
                let dt = data.endDate.timeIntervalSince(prevTime)
                if dt > 0.5, d >= prev {
                    kmh = (d - prev) / dt * 3.6
                }
            }
            self.lastDistance = data.distance?.doubleValue
            self.lastTime = data.endDate

            let speed = kmh.isFinite && kmh > 0 ? min(kmh, 90) : 0
            DispatchQueue.main.async {
                self.onSpeed?(speed)
            }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        lastDistance = nil
        lastTime = nil
    }
}
