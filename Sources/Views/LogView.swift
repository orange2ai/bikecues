import SwiftUI
import HealthKit

struct LogView: View {
    @EnvironmentObject var engine: RideEngine
    @State private var workouts: [HKWorkout] = []
    @State private var workoutToDelete: HKWorkout?
    @State private var deleteFailed = false
    @State private var shareItems: [Any] = []
    @State private var exporting = false
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if loading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在读取苹果健康…")
                        }
                        .font(.footnote)
                        .foregroundStyle(.gray)
                        .padding(.top, 20)
                    } else if workouts.isEmpty {
                        Text("暂无骑行记录。若健康里明明有，请到 系统设置 > 隐私与安全 > 健康 > 咕咕骑车 打开读取权限。")
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
                    Text("每条记录右上角的分享按钮，可以把这条骑行全量导出成 Markdown，供人和 agent 分析。")
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
                            workouts = await HealthKitStore.shared.recentWorkouts()
                        } else {
                            deleteFailed = true
                        }
                    }
                }
                Button("取消", role: .cancel) { workoutToDelete = nil }
            } message: {
                Text("只有咕咕或本机有权限的数据能删除，来自其他来源的记录可能删除失败。")
            }
            .alert("删除失败，这条记录不是咕咕写入的，苹果健康不允许跨来源删除。", isPresented: $deleteFailed) {
                Button("好", role: .cancel) {}
            }
            .sheet(isPresented: Binding(get: { !shareItems.isEmpty },
                                        set: { if !$0 { shareItems = [] } })) {
                ShareSheet(items: shareItems)
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
                Button {
                    exportFull(w)
                } label: {
                    if exporting {
                        ProgressView().frame(width: 34, height: 34)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .frame(width: 34, height: 34)
                            .background(Color(white: 0.12))
                            .clipShape(Circle())
                    }
                }
                .disabled(exporting)
            }
            HStack(spacing: 14) {
                Text(MeasurementFormatter.km(w.totalDistance))
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

    private func load() async {
        loading = true
        try? await HealthKitStore.shared.requestAuthorization()
        workouts = await HealthKitStore.shared.recentWorkouts()
        loading = false
    }

    /// 全量导出：这条训练在苹果健康里可读的一切
    private func exportFull(_ w: HKWorkout) {
        exporting = true
        Task {
            let text = await Self.fullMarkdown(for: w)
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "咕咕骑车-\(f.string(from: w.startDate)).md")
            try? text.write(to: url, atomically: true, encoding: .utf8)
            await MainActor.run {
                exporting = false
                shareItems = [url]
            }
        }
    }

    private static func fullMarkdown(for w: HKWorkout) async -> String {
        async let hrTask = HealthKitStore.shared.heartRateSamples(for: w)
        async let cadenceTask = HealthKitStore.shared.cadenceSamples(for: w)
        async let distTask = HealthKitStore.shared.distanceSamples(for: w)
        let hr = await hrTask
        let cadence = await cadenceTask
        let dist = await distTask
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let t = DateFormatter(); t.dateFormat = "HH:mm:ss"

        let km = w.totalDistance.map { String(format: "%.2f", $0.doubleValue(for: .meter()) / 1000) } ?? "--"
        let energy = w.totalEnergyBurned.map { String(format: "%.0f 千卡", $0.doubleValue(for: .kilocalorie())) } ?? "--"
        let avgHR = hr.isEmpty ? nil : hr.map { $0.1 }.reduce(0, +) / Double(hr.count)
        let maxHR = hr.map { $0.1 }.max()

        var lines = ["""
        # 骑行 · \(f.string(from: w.startDate))

        - 距离: \(km) km
        - 用时: \(Int(w.duration) / 60) 分钟
        - 消耗: \(energy)
        - 平均心率: \(avgHR.map { String(format: "%.0f bpm", $0) } ?? "--")
        - 最大心率: \(maxHR.map { String(format: "%.0f bpm", $0) } ?? "--")
        - 数据来源: \(w.sourceRevision.source.name)
        - 记录设备: \(w.device?.name ?? "--")

        > 由 咕咕骑行 Coucou Bike 全量导出自苹果健康 · 供人阅读，也供 agent 分析
        """]

        // 每公里分段：从距离样本流的累计值算，配该时段平均心率
        let splits = Self.kmSplits(from: dist)
        if !splits.isEmpty {
            lines.append("\n## 每公里分段\n")
            lines.append("| 公里 | 用时 | 均速 km/h | 平均心率 |\n|---|---|---|---|")
            var segStart = dist.first?.0 ?? w.startDate
            for (i, segEnd) in splits.enumerated() {
                let seconds = segEnd.timeIntervalSince(segStart)
                let speed = seconds > 1 ? 3600.0 / seconds : 0
                let segHR = hr.filter { $0.0 >= segStart && $0.0 <= segEnd }
                let avg = segHR.isEmpty ? "--" : String(format: "%.0f", segHR.map { $0.1 }.reduce(0, +) / Double(segHR.count))
                let mm = Int(seconds) / 60, ss = Int(seconds) % 60
                lines.append(String(format: "| %d | %d:%02d | %.1f | %@ |", i + 1, mm, ss, speed, avg))
                segStart = segEnd
            }
        }

        if !hr.isEmpty {
            lines.append("\n## 心率（\(hr.count) 条）\n")
            lines.append("| 时间 | 心率 bpm |\n|---|---|")
            for (date, bpm) in hr {
                lines.append("| \(t.string(from: date)) | \(Int(bpm)) |")
            }
        }
        if !cadence.isEmpty {
            lines.append("\n## 踏频（\(cadence.count) 条）\n")
            lines.append("| 时间 | 踏频 rpm |\n|---|---|")
            for (date, rpm) in cadence {
                lines.append("| \(t.string(from: date)) | \(Int(rpm)) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// 把距离样本流换算成每公里节点时间。兼容累计值与增量两种写入习惯。
    private static func kmSplits(from samples: [(Date, Double)]) -> [Date] {
        guard samples.count > 1 else { return [] }
        var splits: [Date] = []
        var cum = 0.0
        var nextKm = 1000.0
        var prevMeters: Double?
        for (date, meters) in samples {
            let delta: Double
            if let prev = prevMeters {
                delta = meters >= prev ? meters - prev : meters
            } else {
                delta = 0
            }
            prevMeters = meters
            cum += max(0, delta)
            while cum >= nextKm {
                splits.append(date)
                nextKm += 1000
            }
        }
        return splits
    }
}

extension MeasurementFormatter {
    static func km(_ q: HKQuantity?) -> String {
        guard let q else { return "0.0 km" }
        return String(format: "%.1f km", q.doubleValue(for: .meter()) / 1000)
    }
}

import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
