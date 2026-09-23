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

/// 撒花：左右两发礼炮从下角往里喷，拋物线 + 空气阻尼，翻滚收最后淡出
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id: Int
        let x0: CGFloat          // 起点横纵（占屏比）
        let y0: CGFloat
        let vx0: CGFloat         // 初速 pt/s（vx0 向内，vy0 负 = 向上）
        let vy0: CGFloat
        let size: CGFloat
        let color: Color
        let spinRate: Double     // 翻滚角速度 deg/s
        let round: Bool
        let delay: Double
        let life: Double         // 寿命秒，到期必淡出
    }

    // 线性空气阻尼系数与重力（pt/s²），闭式解用
    private static let drag: Double = 1.4
    private static let gravity: Double = 1500

    private let pieces: [Piece] = (0..<90).map { i in
        let left = i % 2 == 0
        let angle = Double.random(in: 55...80) * .pi / 180   // 与水平夹角
        let speed = Double.random(in: 550...950)
        let dir: Double = left ? 1 : -1
        return Piece(
            id: i,
            x0: left ? 0.04 : 0.96,
            y0: 0.92,
            vx0: CGFloat(dir * cos(angle) * speed),
            vy0: CGFloat(-sin(angle) * speed),
            size: .random(in: 6...12),
            color: [Color.orange, Color.orange, Color.yellow, Color.white, Color(white: 0.5)].randomElement()!,
            spinRate: .random(in: 120...420) * (Bool.random() ? 1 : -1),
            round: Bool.random(),
            delay: .random(in: 0...0.35),
            life: .random(in: 2.6...3.6)
        )
    }

    private let startedAt = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(startedAt)
            GeometryReader { geo in
                ForEach(pieces) { p in
                    let age = t - p.delay
                    if age > 0, age < p.life {
                        let e = exp(-Self.drag * age)
                        let inv = (1 - e) / Self.drag
                        let x = p.x0 * geo.size.width + p.vx0 * inv
                        let y = p.y0 * geo.size.height + (p.vy0 + Self.gravity / Self.drag) * inv - (Self.gravity / Self.drag) * age
                        let raw = age / p.life
                        shape(p)
                            .frame(width: p.size, height: p.round ? p.size : p.size * 0.55)
                            .position(x: x, y: y)
                            .rotationEffect(.degrees(p.spinRate * inv))
                            .opacity(raw > 0.72 ? (1 - raw) / 0.28 : 1)
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
