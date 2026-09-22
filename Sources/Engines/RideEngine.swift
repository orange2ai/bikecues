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
    @Published var screenDimmed = false
    @Published var healthAuthorized = false

    enum Phase { case idle, riding, paused }

    // MARK: - 内部
    private let recorder = LocationRecorder()
    private let hk = HealthKitStore.shared
    private var startDate: Date?
    private var pausedAccum: TimeInterval = 0
    private var lastPauseStart: Date?
    private var lastKm = 0
    private var lastZone: HRZone?
    private var lastIntervalCue: Date?
    private var ticker: Timer?
    private var idleTimer: Timer?
    private var lastInteraction = Date()

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
        CueSpeaker.shared.activateSession(mixWithOthers: settings.mixWithAudio)
        cue("已开始记录，骑码陪你出发", kind: .lifecycle)

        phase = .riding
        startTicker()
        resetIdle()
    }

    func pause() {
        guard phase == .riding else { return }
        phase = .paused
        lastPauseStart = Date()
        recorder.stop()
        cue("已暂停", kind: .lifecycle)
        resetIdle()
    }

    func resume() {
        guard phase == .paused else { return }
        pausedAccum += Date().timeIntervalSince(lastPauseStart ?? Date())
        phase = .riding
        recorder.start()
        cue("继续骑行", kind: .lifecycle)
        resetIdle()
    }

    func endRide() {
        guard phase != .idle else { return }
        let end = Date()
        recorder.stop()
        hk.endWorkout(end: end)
        CueSpeaker.shared.deactivateSession()
        stopTicker()
        phase = .idle
        screenDimmed = false
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
        evaluateDim(now: Date())

        // 心率兜底源：定时从 HealthKit 捞最新心率（延迟源）
        if state.heartRateSource == .none || state.heartRateSource == .healthKit {
            Task { [weak self] in
                let hr = await HealthKitStore.shared.latestHeartRate()
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
    }

    // MARK: - 触发器

    private func checkTriggers() {
        let avg = state.averageSpeedKmh

        // 每公里
        if settings.perKilometer {
            let km = Int(state.distanceKm)
            if km > lastKm {
                lastKm = km
                let m = Int(state.elapsed) / 60, s = Int(state.elapsed) % 60
                cue("第 \(km) 公里，用时 \(m) 分 \(String(format: "%02d", s)) 秒，平均速度 \(Int(avg)) 公里每小时", kind: .kmSplit)
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

    private func cue(_ text: String, kind: CueKind) {
        let event = CueEvent(id: UUID(), date: Date(), text: text, kind: kind)
        cues.insert(event, at: 0)
        if cues.count > 100 { cues.removeLast() }
        CueSpeaker.shared.speak(text)
        if kind != .lifecycle {
            wakeScreenForCue()
        }
    }

    // MARK: - 省电（OLED：纯黑即熄灭 + 静置调暗 + 定时自亮）

    func userInteracted() {
        lastInteraction = Date()
        if screenDimmed { screenDimmed = false }
    }

    func resetIdle() {
        lastInteraction = Date()
        screenDimmed = false
    }

    private func wakeScreenForCue() {
        guard settings.wakeOnCue, phase == .riding else { return }
        if screenDimmed { screenDimmed = false }
        let delay = TimeInterval(settings.glowDurationSeconds)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, self.phase == .riding, self.settings.dimOnIdle else { return }
            self.screenDimmed = Date().timeIntervalSince(self.lastInteraction) >= TimeInterval(self.settings.dimDelaySeconds)
        }
    }

    /// 由界面层每秒调用：判断是否应进入息屏 / 定时自亮
    func evaluateDim(now: Date) {
        guard phase == .riding, settings.dimOnIdle else { return }
        let idle = now.timeIntervalSince(lastInteraction)
        if screenDimmed {
            if idle >= TimeInterval(settings.glowIntervalSeconds) {
                screenDimmed = false // 自亮 glowDuration 后由下次 evaluate 重新调暗
            }
        } else if idle >= TimeInterval(settings.dimDelaySeconds) {
            screenDimmed = true
        }
    }

    /// 真实亮度控制由视图层根据 screenDimmed 调 UIScreen.brightness（模拟器上无效但真机有效）

    func saveSettings() {
        settings.save()
        CueSpeaker.shared.setVoice(name: settings.voiceName)
    }

    func exportLatestRideMarkdown() -> String {
        let date = startDate ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines = [
            "# 骑行 · \(formatter.string(from: date))",
            "",
            "- 距离: \(String(format: \"%.2f\", state.distanceKm)) km",
            "- 用时: \(Int(state.elapsed / 60)) 分钟",
            "- 平均速度: \(String(format: \"%.1f\", state.averageSpeedKmh)) km/h",
            "- 心率源: \(state.heartRateSource.rawValue)\(state.heartRate.map { \" · 最新 \(Int($0)) bpm\" } ?? \"\")",
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
