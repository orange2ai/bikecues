import SwiftUI

struct RideView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        Group {
            switch engine.phase {
            case .idle: idleView
            case .riding, .paused: liveView
            }
        }
        .background(.black)
    }

    // MARK: - 未开始
    private var idleView: some View {
        ZStack {
            VStack(spacing: 18) {
                Text("骑 码")
                    .font(.system(size: 15, weight: .medium))
                    .tracking(6)
                    .foregroundStyle(.gray)
                Button(action: { engine.startRide() }) {
                    Text("GO")
                        .font(.system(size: 44, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 168, height: 168)
                        .background(Circle().fill(Color.orange))
                        .shadow(color: .orange.opacity(0.25), radius: 30)
                }
                Text("记录与播报 · 数据存入苹果健康 · 永不丢失")
                    .font(.footnote)
                    .foregroundStyle(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 骑行中（沉浸：无页签，纯黑 OLED）
    private var liveView: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .strokeBorder(engine.phase == .paused ? Color.gray : Color.white, lineWidth: 1.5)
                        .background(Circle().fill(engine.phase == .paused ? Color.clear : Color.white))
                        .frame(width: 7, height: 7)
                    Text(engine.phase == .paused ? "已暂停" : "记录中")
                }
                .foregroundStyle(.gray)
                .font(.caption)
                Spacer()
                Text(Date(), style: .time)
                    .foregroundStyle(.gray)
                    .font(.caption)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            Spacer(minLength: 0)

            // 速度
            VStack(spacing: 4) {
                Text("\(Int(engine.state.speedKmh))")
                    .font(.system(size: 116, weight: .ultraLight))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("KM/H")
                    .font(.caption2)
                    .tracking(4)
                    .foregroundStyle(.gray)
            }

            // 距离 + 心率：两块大字
            HStack(spacing: 0) {
                bigMetric(value: String(format: "%.2f", engine.state.distanceKm), unit: "距离 KM")
                Rectangle().fill(Color(white: 0.14)).frame(width: 1, height: 64)
                bigMetric(value: engine.state.heartRate.map { "\(Int($0))" } ?? "—", unit: "心率 BPM")
            }
            .padding(.top, 20)

            Spacer(minLength: 0)

            // 辅助行
            HStack {
                auxStat(value: String(format: "%.1f", engine.state.averageSpeedKmh), label: "均速")
                auxStat(value: timeString(engine.state.elapsed), label: "用时")
                auxStat(value: engine.state.cadence.map { "\(Int($0))" } ?? "—", label: "踏频")
                auxStat(value: "\(Int(engine.state.calories))", label: "千卡")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

            // 最新播报
            Text(engine.cues.first?.text ?? " ")
                .font(.footnote)
                .foregroundStyle(engine.cues.first.map { Date().timeIntervalSince($0.date) < 4 ? Color.white : Color.gray } ?? .gray)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 24)
                .frame(minHeight: 38)

            // 单键：点按暂停 / 长按结束
            MainHoldButton(
                paused: engine.phase == .paused,
                onTap: { engine.phase == .paused ? engine.resume() : engine.pause() },
                onLongPress: { engine.endRide() }
            )
            .padding(.horizontal, 22)
            .padding(.bottom, 28)
        }
        .contentShape(Rectangle())
    }

    private func bigMetric(value: String, unit: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 52, weight: .light))
                .monospacedDigit()
            Text(unit)
                .font(.caption2)
                .tracking(3)
                .foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func auxStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout).monospacedDigit().foregroundStyle(.white)
            Text(label).font(.caption2).foregroundStyle(.gray)
        }
        .frame(maxWidth: .infinity)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

/// 单键：点按 = 暂停/继续，长按 1.2 秒 = 结束
struct MainHoldButton: View {
    let paused: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    @State private var progress: CGFloat = 0
    @State private var holding = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(progress * 0.14))
            Text(paused ? "继续 · 长按结束" : "暂停 · 长按结束")
                .font(.system(size: 15, weight: .medium))
                .tracking(2)
                .foregroundStyle(.white)
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color(white: 0.24), lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .gesture(
            LongPressGesture(minimumDuration: 1.2)
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onChanged { state in
                    switch state {
                    case .first(true):
                        holding = true
                        withAnimation(.linear(duration: 1.2)) { progress = 1 }
                    default: break
                    }
                }
                .onEnded { _ in
                    holding = false
                    progress = 0
                    onLongPress()
                }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                guard !holding else { return }
                onTap()
            }
        )
    }
}
