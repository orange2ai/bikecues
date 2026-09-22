import SwiftUI

struct CuesView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        NavigationStack {
            List {
                Section("触发") {
                    toggleRow("每公里播报", sub: "距离、用时、当前速度、平均速度", $engine.settings.perKilometer)
                    stepperRow("定时播报", sub: "听播客时的低频报数", value: engine.settings.intervalMinutes == 0 ? "关" : "\(engine.settings.intervalMinutes) 分钟") {
                        engine.settings.intervalMinutes = max(0, engine.settings.intervalMinutes - 5)
                    } plus: {
                        engine.settings.intervalMinutes = min(60, engine.settings.intervalMinutes + 5)
                    }
                    toggleRow("心率区间提醒", sub: "进出区间时播报当前心率", $engine.settings.hrZoneAlert)
                    toggleRow("配速异常提醒", sub: "速度突然掉崖时提醒你（爆胎那种）", $engine.settings.paceAnomaly)
                }
                Section("音频") {
                    toggleRow("混音播放", sub: "播报压低音乐音量，不暂停不打断", $engine.settings.mixWithAudio)
                }
            }
            .navigationTitle("播报")
        }
    }

    private func toggleRow(_ name: String, sub: String, _ binding: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: binding)
                .labelsHidden()
                .tint(.orange)
        }
        .onChange(of: binding.wrappedValue) { _, _ in engine.saveSettings() }
    }

    private func stepperRow(_ name: String, sub: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("−", action: minus)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Color(white: 0.15))
                .clipShape(Circle())
            Text(value)
                .monospacedDigit()
                .frame(minWidth: 64)
            Button("+", action: plus)
                .font(.title3)
                .frame(width: 34, height: 34)
                .background(Color(white: 0.15))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
