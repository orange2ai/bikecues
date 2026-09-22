import SwiftUI

struct CuesView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    group("触发") {
                        toggleRow("每公里播报", sub: "距离、用时、当前速度、平均速度", $engine.settings.perKilometer)
                        stepperRow("定时播报", sub: "听播客时的低频报数", value: engine.settings.intervalMinutes == 0 ? "关" : "\(engine.settings.intervalMinutes) 分钟") {
                            engine.settings.intervalMinutes = max(0, engine.settings.intervalMinutes - 5)
                        } plus: {
                            engine.settings.intervalMinutes = min(60, engine.settings.intervalMinutes + 5)
                        }
                        toggleRow("心率区间提醒", sub: "进出区间时播报当前心率", $engine.settings.hrZoneAlert)
                        toggleRow("配速异常提醒", sub: "速度突然掉崖时提醒你（爆胎那种）", $engine.settings.paceAnomaly)
                    }
                    group("音频") {
                        toggleRow("混音播放", sub: "播报压低音乐音量，不暂停不打断", $engine.settings.mixWithAudio)
                    }
                    Text("骑码只在耳机里说话。屏幕上永远没有弹窗广告，没有开屏广告，没有商城入口。")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                        .padding(.horizontal, 4)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("播报")
        }
    }

    @ViewBuilder
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.subheadline).foregroundStyle(.gray).padding(.bottom, 8)
            VStack(spacing: 0) {
                content()
            }
            .background(Color(white: 0.07))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    private func toggleRow(_ name: String, sub: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(sub).font(.caption).foregroundStyle(.gray)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.orange)
        }
        .padding(14)
        .onChange(of: binding.wrappedValue) { _, _ in engine.saveSettings() }
    }

    private func stepperRow(_ name: String, sub: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(sub).font(.caption).foregroundStyle(.gray)
            }
            Spacer()
            Button("−", action: minus).frame(width: 30, height: 30)
            Text(value).font(.body).monospacedDigit().frame(minWidth: 52)
            Button("+", action: plus).frame(width: 30, height: 30)
        }
        .padding(14)
    }
}
