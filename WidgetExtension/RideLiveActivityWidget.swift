import WidgetKit
import SwiftUI
import ActivityKit

@main
struct CoucouWidgetBundle: WidgetBundle {
    var body: some Widget {
        RideLiveActivityWidget()
    }
}

/// 骑行实时活动：锁屏卡片 + 灵动岛。数据由 App 侧 RideLiveActivity 每秒推送
struct RideLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            LockScreenRideView(state: context.state)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("距离")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text("\(context.state.distanceKm, specifier: "%.2f") km")
                            .font(.title3).fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("心率")
                            .font(.caption2).foregroundStyle(.secondary)
                        if let hr = context.state.heartRate {
                            Label("\(Int(hr))", systemImage: "heart.fill")
                                .font(.title3).fontWeight(.semibold)
                                .foregroundStyle(.red)
                                .monospacedDigit()
                        } else {
                            Text("--").font(.title3).foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("\(Int(context.state.speedKmh)) km/h", systemImage: "speedometer")
                        Spacer()
                        Text(Self.timeString(context.state.elapsed))
                        if context.state.paused {
                            Text("已暂停").foregroundStyle(.orange)
                        }
                    }
                    .font(.footnote).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "figure.outdoor.cycle")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text("\(Int(context.state.speedKmh))")
                    .font(.callout).fontWeight(.semibold)
                    .monospacedDigit().foregroundStyle(.orange)
            } minimal: {
                Text("\(Int(context.state.speedKmh))")
                    .font(.caption).fontWeight(.semibold)
                    .monospacedDigit().foregroundStyle(.orange)
            }
        }
    }

    static func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// 锁屏卡片：黑底 OLED，速度为主角
struct LockScreenRideView: View {
    let state: RideActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state.paused ? "已暂停" : "骑行中", systemImage: "figure.outdoor.cycle")
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(state.paused ? Color.yellow : Color.orange)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(state.speedKmh, specifier: "%.1f")")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.orange)
                    Text("km/h")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.distanceKm, specifier: "%.2f") km")
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(RideLiveActivityWidget.timeString(state.elapsed))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            if let hr = state.heartRate {
                Label("\(Int(hr)) bpm", systemImage: "heart.fill")
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.red)
                    .monospacedDigit()
            }
        }
        .padding()
    }
}
