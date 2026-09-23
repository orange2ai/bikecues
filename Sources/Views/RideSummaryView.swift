import SwiftUI

/// 结束骑行后的结算页：数据汇总 + 撒花，仪式感收尾
struct RideSummaryView: View {
    @EnvironmentObject var engine: RideEngine

    private var state: RideState { engine.state }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ConfettiView()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Text("骑完啦")
                        .font(.system(size: 44, weight: .heavy))
                        .tracking(2)
                    if engine.settings.emotionalValue {
                        Text(PraisePool.finish(distanceKm: state.distanceKm))
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }

                // 主角：距离
                VStack(spacing: 6) {
                    Text(String(format: "%.2f", state.distanceKm))
                        .font(.system(size: 96, weight: .ultraLight))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("公里")
                        .font(.caption)
                        .tracking(6)
                        .foregroundStyle(.gray)
                }
                .padding(.top, 30)

                Spacer()

                // 数据网格
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 26) {
                    summaryStat(timeString(state.elapsed), "用时")
                    summaryStat(String(format: "%.1f", state.averageSpeedKmh), "均速 KM/H")
                    summaryStat(String(format: "%.1f", state.maxSpeedKmh), "最高速 KM/H")
                    summaryStat("\(Int(state.calories))", "千卡")
                    if let avgHr = averageHeartRate {
                        summaryStat("\(Int(avgHr))", "平均心率")
                        summaryStat(engine.rideMaxHr.map { "\(Int($0))" } ?? "—", "最高心率")
                    }
                }
                .padding(.horizontal, 16)

                Text("数据已写入苹果健康")
                    .font(.caption2)
                    .tracking(2)
                    .foregroundStyle(Color(white: 0.4))
                    .padding(.top, 30)

                Button(action: { withAnimation(.easeOut(duration: 0.25)) { engine.showSummary = false } }) {
                    Text("完成")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(4)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(RoundedRectangle(cornerRadius: 27).fill(Color.orange))
                }
                .padding(.horizontal, 30)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
        }
        .statusBarHidden()
    }

    private var averageHeartRate: Double? {
        engine.rideHrCount > 0 ? engine.rideHrSum / Double(engine.rideHrCount) : nil
    }

    private func summaryStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 26, weight: .light))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .tracking(2)
                .foregroundStyle(.gray)
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t)
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60) }
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

/// 撒花：结束时立刻飘落，自由落体 + 左右摇摆，尾段淡出，保证完全消失不残留
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x0: CGFloat         // 水平起点 0...1
        let delay: Double
        let duration: Double
        let size: CGFloat
        let color: Color
        let spin: Double        // 总旋转角
        let sway: CGFloat       // 左右摆幅
        let swayFreq: Double    // 摆动次数
        let round: Bool         // 圆片或纸屑
    }

    private let pieces: [Piece] = (0..<110).map { i in
        Piece(
            id: i,
            x0: .random(in: 0...1),
            delay: .random(in: 0...0.5),
            duration: .random(in: 2.2...4.0),
            size: .random(in: 6...12),
            color: [Color.orange, Color.orange, Color.yellow, Color.white, Color(white: 0.5)].randomElement()!,
            spin: .random(in: 240...760) * (Bool.random() ? 1 : -1),
            sway: .random(in: 18...55),
            swayFreq: .random(in: 1...2.5),
            round: Bool.random()
        )
    }

    private let startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startedAt)
            GeometryReader { geo in
                let total = geo.size.height + 120
                ForEach(pieces) { p in
                    let raw = (t - p.delay) / p.duration
                    if raw > 0, raw < 1 {
                        // 平方递进 = 重力加速感
                        let prog = raw * raw
                        shape(p)
                            .frame(width: p.size, height: p.round ? p.size : p.size * 0.55)
                            .position(
                                x: p.x0 * geo.size.width + sin(raw * .pi * p.swayFreq * 2) * p.sway,
                                y: -60 + total * prog
                            )
                            .rotationEffect(.degrees(p.spin * raw))
                            .opacity(raw > 0.85 ? (1 - raw) / 0.15 : 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func shape(_ p: Piece) -> some View {
        if p.round {
            Circle().fill(p.color)
        } else {
            RoundedRectangle(cornerRadius: 1.5).fill(p.color)
        }
    }
}
