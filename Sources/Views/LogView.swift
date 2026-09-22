import SwiftUI
import HealthKit

struct LogView: View {
    @EnvironmentObject var engine: RideEngine
    @State private var workouts: [HKWorkout] = []
    @State private var mdPreview = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        Text("与苹果健康双向同步 · 数据永不丢失")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                    }
                    .padding(.horizontal, 4)

                    if workouts.isEmpty {
                        Text("暂无骑行记录。第一次骑行结束后会出现在这里。")
                            .font(.footnote)
                            .foregroundStyle(.gray)
                            .padding(.top, 20)
                    } else {
                        ForEach(workouts, id: \.uuid) { w in
                            workoutCard(w)
                        }
                    }

                    Text("数据出口").font(.headline).padding(.top, 10)
                    Text("你的数据可以随时离开骑码，一个字都不会少")
                        .font(.caption)
                        .foregroundStyle(.gray)
                    Button {
                        exportMarkdown()
                    } label: {
                        Text("导出为 Markdown")
                            .font(.callout)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: 1.5))
                            .foregroundStyle(.orange)
                    }
                    if mdPreview {
                        Text(sampleMarkdown)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.gray)
                            .padding(12)
                            .background(Color(white: 0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .navigationTitle("记录")
            .task { workouts = await HealthKitStore.shared.recentWorkouts() }
        }
    }

    private func workoutCard(_ w: HKWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w.startDate, format: .dateTime.month().day().weekday())
                    .font(.subheadline).bold()
                Spacer()
                Text("\(MeasurementFormatter.km(w.totalDistance))")
                    .font(.title3).bold().monospacedDigit().foregroundStyle(.orange)
            }
            HStack(spacing: 14) {
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

    private func exportMarkdown() {
        withAnimation { mdPreview = true }
        let text = RideEngine.shared.exportLatestRideMarkdown()
        let url = FileManager.default.temporaryDirectory.appending(path: "ride-\(Int(Date().timeIntervalSince1970)).md")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private var sampleMarkdown: String {
        """
        # 骑行 · \(Date().formatted(date: .abbreviated, time: .shortened))

        - 距离: \(String(format: "%.1f", RideEngine.shared.state.distanceKm)) km
        - 用时: \(Int(RideEngine.shared.state.elapsed / 60)) 分钟
        - 平均速度: \(String(format: "%.1f", RideEngine.shared.state.averageSpeedKmh)) km/h
        - 平均心率: \(RideEngine.shared.state.heartRate.map { "\(Int($0))" } ?? "--") bpm

        > 由 骑码 bikecues 导出 · 供人阅读，也供 agent 分析
        """
    }
}

extension MeasurementFormatter {
    static func km(_ q: HKQuantity?) -> String {
        guard let q else { return "0.0 km" }
        return String(format: "%.1f km", q.doubleValue(for: .meter()) / 1000)
    }
}
