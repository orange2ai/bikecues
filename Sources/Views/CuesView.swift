import SwiftUI

struct CuesView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        NavigationStack {
            List {
                Section("触发") {
                    toggleRow("每公里播报", sub: "距离、用时、当前速度、平均速度", $engine.settings.perKilometer)
                    stepperRow("定时播报", sub: "听播客时的低频报数", value: engine.settings.intervalMinutes == 0 ? "关" : "\(engine.settings.intervalMinutes) 分钟", binding: $engine.settings.intervalMinutes)
                    toggleRow("心率区间提醒", sub: "进出区间时播报当前心率", $engine.settings.hrZoneAlert)
                    toggleRow("情绪价值", sub: "夸夸你，多邻国那种劲儿", $engine.settings.emotionalValue)
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

    private func stepperRow(_ name: String, sub: String, value: String, binding: Binding<Int>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                Text(sub)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Stepper("", onIncrement: {
                binding.wrappedValue = min(60, binding.wrappedValue + 5)
                engine.saveSettings()
            }, onDecrement: {
                binding.wrappedValue = max(0, binding.wrappedValue - 5)
                engine.saveSettings()
            })
            .labelsHidden()
            .fixedSize()
        }
    }
}
