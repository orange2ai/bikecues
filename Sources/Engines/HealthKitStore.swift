import Foundation
import HealthKit

/// HealthKit 读写：训练写入 + 心率读取（延迟兜底）+ 历史查询
final class HealthKitStore {
    static let shared = HealthKitStore()
    private let store = HKHealthStore()

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

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

    func endWorkout(end: Date) {
        guard let builder else { return }
        builder.endCollection(withEnd: end) { _, _ in
            builder.finishWorkout { _, _ in }
        }
        self.builder = nil
    }

    // MARK: - 心率读取（延迟兜底源）

    /// 查询最近 N 秒内的心率样本（HealthKit 心率有延迟，用于每公里播报等低频场景）
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
