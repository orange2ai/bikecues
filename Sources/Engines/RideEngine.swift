import Foundation
import SwiftUI
import CoreLocation
import UIKit

/// 骑行总引擎：编排 GPS、HealthKit、播报、省电
@MainActor
final class RideEngine: ObservableObject {
    static let shared = RideEngine()

    // MARK: - 发布状态
    @Published var phase: Phase = .idle
    @Published var state = RideState()
    @Published var cues: [CueEvent] = []
    @Published var settings: CueSettings = CueSettings.load()
    @Published var healthAuthorized = false

    enum Phase { case idle, riding, paused }

    // MARK: - 内部
    private let recorder = LocationRecorder()
    private let hk = HealthKitStore.shared
    private var startDate: Date?
    private var pausedAccum: TimeInterval = 0
    private var lastPauseStart: Date?
    private var lastKm = 0
    private var lastKmElapsed: TimeInterval = 0
    private var lastZone: HRZone?
    private var lastIntervalCue: Date?
    private var ticker: Timer?
    // 本公里心率累计（用于“平均心率”播报）
    private var hrSegSum: Double = 0
    private var hrSegCount: Int = 0

    private init() {
        recorder.onLocation = { [weak self] loc in
            self?.absorb(location: loc)
        }
    }

    // MARK: - 生命周期

    func startRide() {
        guard phase == .idle else { return }
        Task { try? await hk.requestAuthorization() }
        recorder.requestPermission()

        let now = Date()
        startDate = now
        lastKm = 0
        lastZone = nil
        lastIntervalCue = now
        pausedAccum = 0
        cues.removeAll()

        recorder.start()
        hk.startWorkout(start: now)
        hk.startLiveHeartRateObservation { [weak self] bpm, endDate in
            Task { @MainActor in
                // 只接受 90 秒内的新鲜样本，过期样本说明手表没有在记录，退回无心率状态
                guard let self, Date().timeIntervalSince(endDate) < 90 else { return }
                self.absorbHeartRate(bpm, source: .healthKit)
            }
        }
        CueSpeaker.shared.activateSession(mixWithOthers: settings.mixWithAudio)
        cue("已开始记录，骑码陪你出发", kind: .lifecycle)

        phase = .riding
        startTicker()
    }

    func pause() {
        guard phase == .riding else { return }
        phase = .paused
        lastPauseStart = Date()
        recorder.stop()
        cue("已暂停", kind: .lifecycle)
    }

    func resume() {
        guard phase == .paused else { return }
        pausedAccum += Date().timeIntervalSince(lastPauseStart ?? Date())
        phase = .riding
        recorder.start()
        cue("继续骑行", kind: .lifecycle)
    }

    func endRide() {
        guard phase != .idle else { return }
        let end = Date()
        recorder.stop()
        hk.stopLiveHeartRateObservation()
        hk.endWorkout(end: end)
        CueSpeaker.shared.deactivateSession()
        stopTicker()
        phase = .idle
        cue("骑行结束，数据已写入苹果健康", kind: .lifecycle)
        // 保留 cues 供结束页展示；新骑行时清空
    }

    // MARK: - 定时器

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {
        guard phase == .riding, let start = startDate else { return }
        state.elapsed = Date().timeIntervalSince(start) - pausedAccum
        state.averageSpeedKmh = state.elapsed > 5 ? state.distanceKm / (state.elapsed / 3600) : 0

        // 模拟器演示模式：GPS 不会移动，注入合成数据让播报可测（60 倍速）
        #if targetEnvironment(simulator)
        if let s = startDate {
            let t = Date().timeIntervalSince(s)
            state.speedKmh = max(4, 23 + sin(t / 7) * 6 + sin(t / 2.3) * 2.5)
            state.distanceKm += state.speedKmh / 3600 * 60
            let hr = min(172, max(98, (state.heartRate ?? 118) + Double.random(in: -2...2.4)))
            absorbHeartRate(hr, source: .healthKit)
        }
        #endif

        // 心率兜底源：定时从 HealthKit 捞最新心率（仅在实时观察未生效时使用）
        if state.heartRateSource == .none {
            Task { [weak self] in
                let hr = await HealthKitStore.shared.latestHeartRate(within: 90)
                guard let self, let hr else { return }
                self.absorbHeartRate(hr, source: .healthKit)
            }
        }

        checkTriggers()
    }

    // MARK: - 数据吸收

    private func absorb(location: CLLocation) {
        guard phase == .riding else { return }
        let kmh = max(0, location.speed * 3.6)
        state.speedKmh = kmh.isFinite ? kmh : 0
        if let prev = lastLocation {
            let d = location.distance(from: prev)
            if d > 8 || kmh > 1.5 {
                state.distanceKm += d / 1000
                hk.addDistanceSample(meters: d, at: location.timestamp)
            }
        }
        lastLocation = location
        state.elevationM = location.altitude
    }

    private var lastLocation: CLLocation?

    func absorbHeartRate(_ bpm: Double, source: HeartRateSource) {
        guard phase == .riding else { return }
        state.heartRate = bpm
        state.heartRateSource = source
        hk.addHeartRateSample(bpm: bpm, at: Date())
        hrSegSum += bpm
        hrSegCount += 1
    }

    // MARK: - 触发器

    private func checkTriggers() {
        let avg = state.averageSpeedKmh

        // 每公里
        if settings.perKilometer {
            let km = Int(state.distanceKm)
            if km > lastKm {
                lastKm = km
                let split = state.elapsed - lastKmElapsed
                lastKmElapsed = state.elapsed
                let splitSpeed = split > 1 ? 3600 / split : state.speedKmh
                let avgHR = hrSegCount > 0 ? hrSegSum / Double(hrSegCount) : state.heartRate
                let hrText = avgHR.map { "，平均心率 \(Int($0))" } ?? ""
                hrSegSum = 0
                hrSegCount = 0
                cue("已经骑行 \(km) 公里，最近一公里平均速度 \(Int(splitSpeed)) 公里\(hrText)", kind: .kmSplit)
            }
        }

        // 定时播报
        if settings.intervalMinutes > 0 {
            let interval = TimeInterval(settings.intervalMinutes * 60)
            if let last = lastIntervalCue, Date().timeIntervalSince(last) >= interval {
                lastIntervalCue = Date()
                cue("已骑行 \(Int(state.distanceKm)) 公里，用时 \(Int(state.elapsed / 60)) 分钟", kind: .interval)
            }
        }

        // 心率区间
        if settings.hrZoneAlert, let hr = state.heartRate {
            let z = HRZone(heartRate: hr)
            if let last = lastZone, z != last {
                cue("心率进入\(z.name)，当前 \(Int(hr))", kind: .hrZone)
            }
            lastZone = z
        }
    }

    // MARK: - 播报

    private func cue(_ text: String, kind: CueEvent.CueKind) {
        let event = CueEvent(id: UUID(), date: Date(), text: text, kind: kind)
        cues.insert(event, at: 0)
        if cues.count > 100 { cues.removeLast() }
        CueSpeaker.shared.speak(text)
    }

    // MARK: - 省电策略：OLED 纯黑即熄灭，骑行页始终 100% 黑底，无需暗屏与亮屏机制

    func saveSettings() {
        settings.save()
    }

    func exportLatestRideMarkdown() -> String {
        let date = startDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let distStr = String(format: "%.2f", state.distanceKm)
        let avgStr = String(format: "%.1f", state.averageSpeedKmh)
        let hrStr = state.heartRate.map { " · 最新 \(Int($0)) bpm" } ?? ""
        var lines = [
            "# 骑行 · \(formatter.string(from: date))",
            "",
            "- 距离: \(distStr) km",
            "- 用时: \(Int(state.elapsed / 60)) 分钟",
            "- 平均速度: \(avgStr) km/h",
            "- 心率源: \(state.heartRateSource.rawValue)\(hrStr)",
            "- 播报记录: \(cues.count) 条",
            "",
            "> 由 骑码 bikecues 导出 · 供人阅读，也供 agent 分析",
        ]
        for c in cues.reversed() {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
            lines.append("- [\(f.string(from: c.date))] \(c.text)")
        }
        return lines.joined(separator: "\n")
    }
}
