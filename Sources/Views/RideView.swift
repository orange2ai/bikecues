import SwiftUI

struct RideView: View {
    @EnvironmentObject var engine: RideEngine
    @State private var showHRHint = false
    @State private var showStartDialog = false
    @State private var deepLinkFailed = false

    // GO 弹窗的状态文案：把心率这件事一次说清楚
    private var startDialogMessage: String {
        if engine.hrAuthDenied {
            return "健康读取权限没开：系统设置 > 隐私与安全 > 健康 > 咕咕骑车，打开后心率才能进来。"
        }
        if engine.state.heartRateSource == .healthKit {
            return "心率已连接。现在开始，咕咕实时播报。"
        }
        return "心率未连接：打开手表体能训练后会自动连上，不用等，直接骑也行。"
    }

    var body: some View {
        Group {
            switch engine.phase {
            case .idle: idleView
            case .riding, .paused: liveView
            }
        }
        .background(.black)
    }

    // MARK: - 未开始：名字在上方，两行，足够大
    private var idleView: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("咕咕骑车")
                    .font(.system(size: 68, weight: .bold))
                    .tracking(2)
                Text("COUCOU BIKE")
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(8)
                    .foregroundStyle(Color.orange)
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()

            Button(action: { showStartDialog = true }) {
                Text("GO")
                    .font(.system(size: 46, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 172, height: 172)
                    .background(Circle().fill(Color.orange))
                    .shadow(color: .orange.opacity(0.25), radius: 30)
            }
            .frame(maxWidth: .infinity)
            .confirmationDialog("准备出发", isPresented: $showStartDialog,
                                titleVisibility: .visible) {
                Button("打开体能训练（记心率）") {
                    if let url = URL(string: "x-apple-fitness://") {
                        UIApplication.shared.open(url) { ok in
                            if !ok { deepLinkFailed = true }
                        }
                    } else {
                        deepLinkFailed = true
                    }
                }
                Button("我已打开，开始骑行") {
                    engine.startRide()
                }
                Button("直接骑行，不用心率") {
                    engine.startRide()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text(startDialogMessage)
            }
            .alert("没打开成功，请手动打开健身 App，选“户外骑行”。", isPresented: $deepLinkFailed) {
                Button("好", role: .cancel) {}
            }

            Spacer()
        }
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

            // 距离 + 心率：两块大字；点心率可提示如何连接
            HStack(spacing: 0) {
                bigMetric(value: String(format: "%.2f", engine.state.distanceKm), unit: "距离 KM")
                Rectangle().fill(Color(white: 0.14)).frame(width: 1, height: 64)
                bigMetric(value: engine.state.heartRate.map { "\(Int($0))" } ?? "—", unit: "心率 BPM")
                    .onTapGesture { showHRHint = true }
            }
            .padding(.top, 20)
            .alert("想看实时心率？", isPresented: $showHRHint) {
                Button("打开体能训练") {
                    if let url = URL(string: "x-apple-fitness://") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("知道了", role: .cancel) {}
            } message: {
                Text("iPhone 没有心率传感器。在手表上开个体能训练，心率会经苹果健康实时显示在这里。")
            }

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
    @State private var holdItem: DispatchWorkItem?
    private let holdDuration: Double = 1.2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(white: 0.10))
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: geo.size.width * progress)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            Text(paused ? "继续 · 长按结束" : "暂停 · 长按结束")
                .font(.system(size: 15, weight: .semibold))
                .tracking(2)
                .foregroundStyle(progress > 0.55 ? Color.black : Color.white)
        }
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard holdItem == nil else { return }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.linear(duration: holdDuration)) { progress = 1 }
                    let item = DispatchWorkItem {
                        holdItem = nil
                        progress = 1
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        onLongPress()
                    }
                    holdItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + holdDuration, execute: item)
                }
                .onEnded { _ in
                    let fired = (holdItem == nil)
                    holdItem?.cancel()
                    holdItem = nil
                    withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
                    guard !fired else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onTap()
                }
        )
    }
}
