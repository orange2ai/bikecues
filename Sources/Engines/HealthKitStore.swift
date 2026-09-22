import Foundation
import HealthKit

/// HealthKit 读写：训练写入 + 心率读取（延迟兜底）+ 历史查询
final class HealthKitStore {
    static let shared = HealthKitStore()
    private let store = HKHealthStore()

    private init() {}

    private var entitled: Bool {
        // 无 HealthKit 能力的构建（临时测试包）里完全不触碰 HealthKit，避免运行时异常
        Bundle.main.object(forInfoDictionaryKey: "BIKECUES_HEALTHKIT") as? Bool ?? false
    }

    var isAvailable: Bool { entitled && HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        guard isAvailable else { return }
        let toShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.cyclingCadence),
        ]
        let toRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        try await store.requestAuthorization(toShare: toShare, read: toRead)
    }

    // MARK: - 训练写入（WorkoutBuilder）

    private var builder: HKWorkoutBuilder?

    func startWorkout(start: Date) {
        guard isAvailable else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .cycling
        config.locationType = .outdoor
        let b = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        b.beginCollection(withStart: start) { _, _ in }
        builder = b
    }

    func addDistanceSample(meters: Double, at date: Date) {
        guard let builder else { return }
        let qty = HKQuantity(unit: .meter(), doubleValue: meters)
        let sample = HKQuantitySample(type: HKQuantityType(.distanceCycling), quantity: qty, start: date, end: date)
        builder.add([sample]) { _, _ in }
    }

    func addHeartRateSample(bpm: Double, at date: Date) {
        guard let builder else { return }
        let qty = HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: bpm)
        let sample = HKQuantitySample(type: HKQuantityType(.heartRate), quantity: qty, start: date, end: date)
        builder.add([sample]) { _, _ in }
    }

    func addEnergySample(kcal: Double, start: Date, end: Date) {
        guard let builder else { return }
        let qty = HKQuantity(unit: .kilocalorie(), doubleValue: kcal)
        let sample = HKQuantitySample(type: HKQuantityType(.activeEnergyBurned), quantity: qty, start: start, end: end)
        builder.add([sample]) { _, _ in }
    }

    func endWorkout(end: Date, completion: ((Bool) -> Void)? = nil) {
        guard let builder else { completion?(false); return }
        self.builder = nil
        builder.endCollection(withEnd: end) { _, _ in
            builder.finishWorkout { _, error in
                if let error { print("[bikecues] finishWorkout error:", error.localizedDescription) }
                DispatchQueue.main.async { completion?(error == nil) }
            }
        }
    }

    // MARK: - 心率读取

    private var hrObserver: HKQuery?
    private var hrAnchor: HKQueryAnchor?

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
}
