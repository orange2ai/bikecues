import Foundation
import CoreLocation
import HealthKit

/// HealthKit 纯读取：咕咕不写入任何数据，记录交给手表原生体能训练。
/// 心率、距离实时监听（AnchoredObjectQuery）+ 历史查询（导出用）。
final class HealthKitStore {
    static let shared = HealthKitStore()
    private let store = HKHealthStore()

    private init() {}

    private var entitled: Bool {
        // 无 HealthKit 能力的构建（临时测试包）里完全不触碰 HealthKit，避免运行时异常。
        // 注意：Info.plist 经构建处理后布尔可能以字符串形式存在，必须两种都认。
        switch Bundle.main.object(forInfoDictionaryKey: "BIKECUES_HEALTHKIT") {
        case let flag as Bool: return flag
        case let flag as String: return ["yes", "1", "true"].contains(flag.lowercased())
        default: return false
        }
    }

    var isAvailable: Bool { entitled && HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        // 只读：不申请任何写入权限
        let toRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.cyclingCadence),
            HKObjectType.workoutType(),
        ]
        try await store.requestAuthorization(toShare: [], read: toRead)
    }

    // MARK: - 历史样本查询（导出用）

    /// 某次体能训练期间的平均心率
    func averageHeartRate(for workout: HKWorkout) async -> Double? {
        let samples = await heartRateSamples(for: workout)
        guard !samples.isEmpty else { return nil }
        return samples.map { $0.1 }.reduce(0, +) / Double(samples.count)
    }

    /// 某次体能训练的心率时间序列
    func heartRateSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        guard isAvailable else { return [] }
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let out = (samples as? [HKQuantitySample])?.map { ($0.endDate, $0.quantity.doubleValue(for: unit)) } ?? []
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// 某次体能训练的踏频时间序列（有则导出，无则空）
    func cadenceSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        guard isAvailable else { return [] }
        let type = HKQuantityType(.cyclingCadence)
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                let out = (samples as? [HKQuantitySample])?.map { ($0.endDate, $0.quantity.doubleValue(for: unit)) } ?? []
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// 某次体能训练的距离样本序列（手表写入，累计值；导出算分段用）
    func distanceSamples(for workout: HKWorkout) async -> [(Date, Double)] {
        guard isAvailable else { return [] }
        let type = HKQuantityType(.distanceCycling)
        let predicate = HKQuery.predicateForSamples(withStart: workout.startDate, end: workout.endDate)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]) { _, samples, _ in
                let out = (samples as? [HKQuantitySample])?.map { ($0.endDate, $0.quantity.doubleValue(for: .meter())) } ?? []
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - 实时监听（只读）

    private var hrObserver: HKQuery?
    private var hrAnchor: HKQueryAnchor?
    private var distObserver: HKQuery?
    private var distAnchor: HKQueryAnchor?

    /// 实时心率观察：手表上跑着任意体能训练时，心率样本约每 5 秒写入 HealthKit，
    /// iPhone 侧用长驻 AnchoredObjectQuery 即可拿到准实时心率，无需手表 App。
    func startLiveHeartRateObservation(handler: @escaping (Double, Date) -> Void) {
        guard isAvailable, hrObserver == nil else { return }
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let q = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: hrAnchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            self.hrAnchor = newAnchor
            for s in samples ?? [] {
                if let hs = s as? HKQuantitySample {
                    let bpm = hs.quantity.doubleValue(for: unit)
                    DispatchQueue.main.async { handler(bpm, hs.endDate) }
                }
            }
        }
        store.execute(q)
        hrObserver = q
    }

    func stopLiveHeartRateObservation() {
        if let q = hrObserver { store.stop(q) }
        hrObserver = nil
        hrAnchor = nil
    }

    /// 实时距离观察：手表体能训练期间距离样本持续写入，
    /// quantity 为累计值（个别来源可能是增量），由调用方兼容处理。
    func startLiveDistanceObservation(handler: @escaping (Double, Date) -> Void) {
        guard isAvailable, distObserver == nil else { return }
        let type = HKQuantityType(.distanceCycling)
        let q = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: distAnchor, limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, newAnchor, _ in
            guard let self else { return }
            self.distAnchor = newAnchor
            for s in samples ?? [] {
                if let hs = s as? HKQuantitySample {
                    let meters = hs.quantity.doubleValue(for: .meter())
                    DispatchQueue.main.async { handler(meters, hs.endDate) }
                }
            }
        }
        store.execute(q)
        distObserver = q
    }

    func stopLiveDistanceObservation() {
        if let q = distObserver { store.stop(q) }
        distObserver = nil
        distAnchor = nil
    }

    /// 查询最近 N 秒内的心率样本（低频兜底）
    func latestHeartRate(within seconds: TimeInterval = 30) async -> Double? {
        guard isAvailable else { return nil }
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-seconds), end: nil)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                guard let s = samples?.first as? HKQuantitySample else { cont.resume(returning: nil); return }
                cont.resume(returning: s.quantity.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    // MARK: - 历史读取

    func recentWorkouts(limit: Int = 20) async -> [HKWorkout] {
        guard isAvailable else { return [] }
        let predicate = HKQuery.predicateForWorkouts(with: .cycling)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: limit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    // MARK: - 删除（仅限有写入权限的数据；他人写入的记录会失败并提示）

    func deleteWorkout(_ w: HKWorkout) async -> Bool {
        guard isAvailable else { return false }
        return await withCheckedContinuation { cont in
            store.delete([w]) { _, error in
                cont.resume(returning: error == nil)
            }
        }
    }
}
