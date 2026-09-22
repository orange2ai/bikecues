import Foundation
import CoreLocation

/// GPS 记录引擎：负责速度、距离、轨迹采集
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    /// 每个新定位点的回调（主线程）
    var onLocation: ((CLLocation) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness          // 骑行优化
        manager.pausesLocationUpdatesAutomatically = false
        // 锁屏/切后台继续记录：when-in-use 授权 + 后台定位模式，系统要求同时显示蓝色指示条
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func start() {
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        lastLocation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 50 else { continue }
            if let prev = lastLocation {
                let d = loc.distance(from: prev)
                // 过滤 GPS 漂移：静止时的小于 8 米位移忽略
                if d > 8 || loc.speed > 1.5 {
                    lastLocation = loc
                    DispatchQueue.main.async { [weak self] in
                        self?.onLocation?(loc)
                    }
                } else {
                    lastLocation = loc
                    DispatchQueue.main.async { [weak self] in
                        self?.onLocation?(loc) // 速度归零类更新也上报，供界面归零
                    }
                }
            } else {
                lastLocation = loc
            }
        }
    }
}
