import SwiftUI
import HealthKit

struct LogView: View {
    @EnvironmentObject var engine: RideEngine
    @State private var workouts: [HKWorkout] = []
    @State private var exportURLs: [UUID: URL] = [:]
    @State private var workoutToDelete: HKWorkout?
    @State private var deleteFailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if workouts.isEmpty {
                        Text("暂无骑行记录。第一次骑行结束后会出现在这里。")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .padding(.top, 20)
                    } else {
                        ForEach(workouts, id: \.uuid) { w in
                            workoutCard(w)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        workoutToDelete = w
                                    } label: {
                                        Label("删除记录", systemImage: "trash")
                                    }
                                }
                        }
                    }

                    Text("导出").font(.headline).padding(.top, 10)
                    Text("每条记录右上角的分享按钮，都可以把这条骑行导出成 Markdown。")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .navigationTitle("记录")
            .confirmationDialog("删除这条骑行记录？",
                                isPresented: Binding(get: { workoutToDelete != nil },
                                                     set: { if !$0 { workoutToDelete = nil } }),
                                titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    guard let w = workoutToDelete else { return }
                    workoutToDelete = nil
                    Task {
                        let ok = await HealthKitStore.shared.deleteWorkout(w)
                        if ok {
                            exportURLs[w.uuid] = nil
                            workouts = await HealthKitStore.shared.recentWorkouts()
                        } else {
                            deleteFailed = true
                        }
                    }
                }
                Button("取消", role: .cancel) { workoutToDelete = nil }
            } message: {
                Text("会同时从苹果健康中删除，无法恢复。")
            }
            .alert("删除失败，请检查苹果健康授权", isPresented: $deleteFailed) {
                Button("好", role: .cancel) {}
            }
            .task { await load() }
        }
    }

    private func workoutCard(_ w: HKWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w.startDate, format: .dateTime.month().day().weekday())
                    .font(.subheadline).bold()
                Spacer()
                HStack(spacing: 4) {
                    if let url = exportURLs[w.uuid] {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.subheadline)
                                .foregroundStyle(.orange)
                                .frame(width: 34, height: 34)
                                .background(Color(white: 0.12))
                                .clipShape(Circle())
                        }
                    }
                    Button {
                        workoutToDelete = w
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.8))
                            .frame(width: 34, height: 34)
                            .background(Color(white: 0.12))
                            .clipShape(Circle())
                    }
                }
            }
            HStack(spacing: 14) {
                Text("\(MeasurementFormatter.km(w.totalDistance))")
                    .font(.title3).bold().monospacedDigit().foregroundStyle(.orange)
                Text(durationString(w.duration))
                if let energy = w.totalEnergyBurned {
                    Text("\(Int(energy.doubleValue(for: .kilocalorie()))) 千卡")
                }
            }
            .font(.caption)
            .foregroundStyle(.gray)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func durationString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d:%02d", Int(t) / 3600, Int(t) % 3600 / 60, Int(t) % 60)
    }

    // MARK: - 加载与导出

    private func load() async {
        workouts = await HealthKitStore.shared.recentWorkouts()
        for w in workouts {
            guard exportURLs[w.uuid] == nil else { continue }
            let hr = await HealthKitStore.shared.averageHeartRate(for: w)
            let text = Self.markdown(for: w, avgHR: hr)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "咕咕骑车-\(f.string(from: w.startDate)).md")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            exportURLs[w.uuid] = url
        }
    }

    private static func markdown(for w: HKWorkout, avgHR: Double?) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let km = w.totalDistance.map { String(format: "%.2f", $0.doubleValue(for: .meter()) / 1000) } ?? "--"
        let hrText = avgHR.map { String(format: "，平均心率 %.0f bpm", $0) } ?? ""
        let energy = w.totalEnergyBurned.map { String(format: "%.0f 千卡", $0.doubleValue(for: .kilocalorie())) } ?? "--"
        return """
        # 骑行 · \(f.string(from: w.startDate))

        - 距离: \(km) km
        - 用时: \(Int(w.duration) / 60) 分钟
        - 消耗: \(energy)\(hrText)

        > 由 咕咕骑行 Coucou Bike 导出 · 供人阅读，也供 agent 分析
        """
    }
}

extension MeasurementFormatter {
    static func km(_ q: HKQuantity?) -> String {
        guard let q else { return "0.0 km" }
        return String(format: "%.1f km", q.doubleValue(for: .meter()) / 1000)
    }
}
