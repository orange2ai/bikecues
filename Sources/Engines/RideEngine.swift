import Foundation
import SwiftUI
import UIKit

/// 骑行总引擎：纯播报编排。记录全部交给手表原生体能训练，
/// 咕咕只监听 HealthKit 的心率与距离样本流，负责说话。
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
    private let hk = HealthKitStore.shared
    private var startDate: Date?
    private var pausedAccum: TimeInterval = 0
    private var lastPauseStart: Date?
    private var lastKm = 0
    private var lastKmElapsed: TimeInterval = 0
    private var lastZone: HRZone?
    private let praise = PraisePicker()
    private var isAutoPaused = false
    private var lowSpeedTicks = 0
    private var ticker: Timer?
    // 本公里心率累计（用于“平均心率”播报）
    private var hrSegSum: Double = 0
    private var hrSegCount: Int = 0
    // 距离样本流：累计值与增量换算
    private var lastDistMeters: Double?
    private var lastDistDate: Date?
    // 无数据提醒
    private var remindedNoData = false

    private init() {}

    // MARK: - 生命周期

    func startRide() {
        guard phase == .idle else { return }
        startDate = Date()
        lastKm = 0
        lastZone = nil
        pausedAccum = 0
        lastDistMeters = nil
        lastDistDate = nil
        remindedNoData = false
        cues.removeAll()

        CueSpeaker.shared.activateSession(mixWithOthers: settings.mixWithAudio)
        cue("咕咕上线，陪你出发", kind: .lifecycle)

        // 记录中屏幕常亮：OLED 纯黑本身几乎不耗电
        UIApplication.shared.isIdleTimerDisabled = true
        phase = .riding
        startTicker()

        Task { @MainActor in
            try? await hk.requestAuthorization()
            self.healthAuthorized = hk.isAvailable
            guard self.phase != .idle else { return }
            self.hk.startLiveHeartRateObservation { [weak self] bpm, endDate in
                Task { @MainActor in
                    // 只接受 90 秒内的新鲜样本，过期样本说明手表没有在记录，退回无心率状态
                    guard let self, Date().timeIntervalSince(endDate) < 90 else { return }
                    self.absorbHeartRate(bpm, source: .healthKit)
                }
            }
            self.hk.startLiveDistanceObservation { [weak self] meters, date in
                Task { @MainActor in
                    guard let self else { return }
                    self.absorbDistance(meters: meters, at: date)
                }
            }
        }
    }

    func pause() {
        guard phase == .riding else { return }
        phase = .paused
        isAutoPaused = false
        lastPauseStart = Date()
        cue(settings.emotionalValue ? "已暂停。" + PraisePool.pause : "已暂停", kind: .lifecycle)
    }

    /// 低速自动暂停：手表端数据停了说明你停了，咕咕跟着闭嘴
    private func autoPause() {
        guard phase == .riding else { return }
        phase = .paused
        isAutoPaused = true
        lastPauseStart = Date()
        cue("已自动暂停，咕咕帮你盯着，动起来就继续", kind: .lifecycle)
    }

    private func autoResume() {
        guard phase == .paused, isAutoPaused else { return }
        pausedAccum += Date().timeIntervalSince(lastPauseStart ?? Date())
        phase = .riding
        isAutoPaused = false
        lowSpeedTicks = 0
        cue("继续骑行，咕咕盯着呢", kind: .lifecycle)
    }

    func resume() {
        guard phase == .paused else { return }
        pausedAccum += Date().timeIntervalSince(lastPauseStart ?? Date())
        phase = .riding
        isAutoPaused = false
        lowSpeedTicks = 0
        cue("继续骑行", kind: .lifecycle)
    }

    func endRide() {
        guard phase != .idle else { return }
        hk.stopLiveHeartRateObservation()
        hk.stopLiveDistanceObservation()
        CueSpeaker.shared.deactivateSession()
        stopTicker()
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .idle

        var text = "骑行结束，数据都在苹果健康里"
        if state.distanceKm > 0 {
            text = String(format: "骑行结束，这趟 %.1f 公里", state.distanceKm)
        }
        if settings.emotionalValue {
            text += "。" + PraisePool.finish(distanceKm: state.distanceKm)
        }
        cue(text, kind: .lifecycle)
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

        // 开跑 45 秒还没有任何数据，多半是忘了开体能训练
        if !remindedNoData, state.elapsed > 45,
           state.distanceKm == 0, state.heartRateSource == .none, settings.hrReminder {
            remindedNoData = true
            cue("咕咕还没听到数据，手表上开个体能训练了吗？", kind: .lifecycle)
        }

        // 低速自动暂停：连续 3 秒低于 1 km/h
        if settings.autoPause {
            if state.speedKmh < 1 {
                lowSpeedTicks += 1
                if lowSpeedTicks >= 3 {
                    lowSpeedTicks = 0
                    autoPause()
                    return
                }
            } else {
                lowSpeedTicks = 0
            }
        }

        // 模拟器演示模式：没有手表数据流，注入合成数据让播报可测（60 倍速）
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

    /// 距离样本流：兼容累计值与增量两种来源，换算出即时速度与总里程
    private func absorbDistance(meters: Double, at date: Date) {
        guard phase != .idle else { return }
        defer {
            lastDistMeters = meters
            lastDistDate = date
        }
        guard let prevMeters = lastDistMeters, let prevDate = lastDistDate else { return }
        let deltaMeters: Double
        if meters >= prevMeters {
            deltaMeters = meters - prevMeters          // 累计值
        } else {
            deltaMeters = meters                        // 增量值
        }
        guard deltaMeters > 0, deltaMeters < 500 else { return } // 过滤倒退与异常跳变
        let dt = max(date.timeIntervalSince(prevDate), 0.1)
        let kmh = deltaMeters / dt * 3.6
        state.distanceKm += deltaMeters / 1000
        let speed = min(kmh, 80).isFinite ? min(kmh, 80) : 0
        state.speedKmh = speed

        // 自动暂停状态下数据重新流动，就继续
        if phase == .paused, isAutoPaused, speed > 3 {
            autoResume()
        }
    }

    func absorbHeartRate(_ bpm: Double, source: HeartRateSource) {
        guard phase != .idle else { return }
        state.heartRate = bpm
        state.heartRateSource = source
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
                var text = "已经骑行 \(km) 公里，最近一公里平均速度 \(Int(splitSpeed)) 公里\(hrText)"
                // 情绪价值：报完正事，三成概率补一句歪嘴夸夸
                if settings.emotionalValue, Double.random(in: 0..<1) < 0.35,
                   let line = praise.pick(from: PraisePool.perKilometer) {
                    text += " " + line
                }
                cue(text, kind: .kmSplit)
            }
        }

        // 心率区间
        if settings.hrZoneAlert, let hr = state.heartRate {
            let z = HRZone(heartRate: hr)
            if let last = lastZone, z != last {
                var text = "心率进入\(z.name)，当前 \(Int(hr))"
                if settings.emotionalValue, z.rawValue > last.rawValue,
                   let line = praise.pick(from: PraisePool.highHeartRate) {
                    text += " " + line
                }
                cue(text, kind: .hrZone)
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
}
