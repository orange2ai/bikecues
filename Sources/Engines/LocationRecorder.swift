import Foundation
import CoreLocation

/// GPS 记录引擎：负责速度、距离、轨迹采集
final class LocationRecorder: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var lastDate: Date?

    /// 每个新定位点的回调（主线程）：位置 + 算好的速度 km/h
    var onLocation: ((CLLocation, Double) -> Void)?
    /// 定位授权状态变化
    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?

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

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways
    }

    /// 必须显式请求，否则系统不会弹授权框，定位一个点都收不到
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        lastLocation = nil
        lastDate = nil
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        lastLocation = nil
        lastDate = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
        if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            guard loc.horizontalAccuracy > 0, loc.horizontalAccuracy < 50 else { continue }

            // 速度兜底：GPS 常常给 -1（无效），用位移除以时间算出来
            var kmh = loc.speed >= 0 ? loc.speed * 3.6 : -1
            if kmh < 0, let prev = lastLocation, let prevDate = lastDate {
                let dt = loc.timestamp.timeIntervalSince(prevDate)
                if dt > 0.5 {
                    kmh = loc.distance(from: prev) / dt * 3.6
                }
            }
            if kmh < 0 { kmh = 0 }
            if !kmh.isFinite { kmh = 0 }

            lastLocation = loc
            lastDate = loc.timestamp
            let speed = min(kmh, 90)
            DispatchQueue.main.async { [weak self] in
                self?.onLocation?(loc, speed)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[coucou][gps] failed:", error.localizedDescription)
    }
}
