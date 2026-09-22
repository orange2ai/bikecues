import SwiftUI
import HealthKit

struct LogView: View {
    @EnvironmentObject var engine: RideEngine
    @State private var workouts: [HKWorkout] = []
    @State private var exportURL: URL?
    @State private var workoutToDelete: HKWorkout?
    @State private var deleting = false

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
                    if let url = exportURL {
                        ShareLink(item: url) {
                            Text("导出为 Markdown")
                                .font(.callout)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange, lineWidth: 1.5))
                                .foregroundStyle(.orange)
                        }
                    }
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
                    deleting = true
                    Task {
                        _ = await HealthKitStore.shared.deleteWorkout(w)
                        workouts = await HealthKitStore.shared.recentWorkouts()
                        deleting = false
                    }
                }
                Button("取消", role: .cancel) { workoutToDelete = nil }
            } message: {
                Text("会同时从苹果健康中删除，无法恢复。")
            }
            .task {
                workouts = await HealthKitStore.shared.recentWorkouts()
                exportURL = prepareExportFile()
            }
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

    private func prepareExportFile() -> URL? {
        let text = RideEngine.shared.exportLatestRideMarkdown()
        let url = FileManager.default.temporaryDirectory.appending(path: "骑码-骑行记录.md")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}

extension MeasurementFormatter {
    static func km(_ q: HKQuantity?) -> String {
        guard let q else { return "0.0 km" }
        return String(format: "%.1f km", q.doubleValue(for: .meter()) / 1000)
    }
}
