import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("数据") {
                        row("苹果健康", sub: "按系统标准写入与读取，不另建孤岛", value: "始终开启", on: true)
                        row("本地优先", sub: "所有记录先落本机，网络只是锦上添花", value: "架构保证", on: true)
                        row("iCloud 同步", sub: "换手机不丢历史，多端一致", value: "规划中", on: false)
                    }

                    section("传感器") {
                        row("Apple Watch 心率", sub: "手表上开个体能训练，心率经苹果健康实时上屏", value: engine.state.heartRateSource == .healthKit ? "已连接" : "未连接", on: engine.state.heartRateSource == .healthKit)
                        row("GPS 速度", sub: "iPhone 定位，无需外设", value: "内置", on: true)
                        row("AirPods Pro 3 / 心率带", sub: "标准蓝牙心率源，实时", value: engine.state.heartRateSource == .bluetooth ? "已连接" : "未连接", on: engine.state.heartRateSource == .bluetooth)
                    }

                    section("咕咕骑车的原则") {
                        principle("01", "省电", "骑行是长时间运动。OLED 纯黑即熄灭，骑行页永远 100% 黑底，不需要变暗的花招。")
                        principle("02", "原生", "和苹果系统深度打通，记录按最兼容的方式写入苹果健康，也读取系统记录。不导流，不另建孤岛。")
                        principle("03", "数据永不丢失", "本地优先，健康兜底，iCloud 同步，Markdown 导出。你的数据属于你，也随时可以离开。")
                        principle("04", "无广告，永久", "永久不出现广告，也不卖货。你买的是软件本身。")
                        principle("05", "开源，仅限自用", "代码公开，欢迎学习和自建。仅限非商业用途，与商店版本互不冲突。")
                        principle("06", "买断制", "一次付费，永久使用，后续功能不另收费。")
                        principle("07", "不发明 UI", "能用苹果就苹果：列表是 List，开关是 Toggle，导出走系统分享。不重新发明系统已经做好的东西。")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .navigationTitle("设置")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 0) { content() }
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
            Toggle("", isOn: binding).labelsHidden().tint(.orange)
        }
        .padding(14)
        .onChange(of: binding.wrappedValue) { _, _ in engine.saveSettings() }
    }

    private func stepperRow(_ name: String, value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack {
            Text(name).font(.body)
            Spacer()
            Button("−", action: minus).frame(width: 30, height: 30)
            Text(value).font(.body).monospacedDigit().frame(minWidth: 52)
            Button("+", action: plus).frame(width: 30, height: 30)
        }
        .padding(14)
    }

    private func row(_ name: String, sub: String, value: String, on: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(sub).font(.caption).foregroundStyle(.gray)
            }
            Spacer()
            Text(value)
                .font(.caption)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(on ? Color.orange.opacity(0.12) : Color(white: 0.12))
                .foregroundStyle(on ? Color.orange : Color.gray)
                .clipShape(Capsule())
        }
        .padding(14)
    }

    private func principle(_ no: String, _ t: String, _ d: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(no).font(.caption).monospacedDigit().foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(t).font(.subheadline).bold()
                Text(d).font(.caption).foregroundStyle(.gray).lineSpacing(3)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
