import SwiftUI

struct SettingsView: View {
    @State private var showHRHint = false
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("骑行") {
                        toggleRow("屏幕常亮", sub: "骑行中不熄屏；关掉也能后台记录与播报", $engine.settings.keepScreenOn)
                        toggleRow("自动暂停", sub: "速度低于 1 km/h 自动暂停，动起来自动继续", $engine.settings.autoPause)
                    }

                    section("传感器") {
                        row("Apple Watch 心率", sub: "手表上开个体能训练，心率经苹果健康实时上屏", value: engine.state.heartRateSource == .healthKit ? "已连接" : "未连接", on: engine.state.heartRateSource == .healthKit)
                            .onTapGesture { showHRHint = true }
                        row("GPS 速度", sub: "iPhone 定位，无需外设", value: "内置", on: true)
                        row("AirPods Pro 3 / 心率带", sub: "标准蓝牙心率源，实时", value: engine.state.heartRateSource == .bluetooth ? "已连接" : "未连接", on: engine.state.heartRateSource == .bluetooth)
                    }

                    section("咕咕骑车的原则") {
                        principle("01", "省电", "骑行是长时间运动。OLED 纯黑即熄灭，骑行页永远 100% 黑底，不需要变暗的花招。")
                        principle("02", "原生", "和苹果系统深度打通，记录按最兼容的方式写入苹果健康，也读取系统记录。不导流，不另建孤岛。")
                        principle("03", "数据永不丢失", "数据都在你的苹果健康与本机，无服务器，随时全量导出 Markdown。你的数据属于你，也随时可以离开。")
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
            .alert("想看实时心率？", isPresented: $showHRHint) {
                Button("打开体能训练") {
                    if let url = URL(string: "x-apple-fitness://") {
                        UIApplication.shared.open(url)
                    }
                }
                Button("知道了", role: .cancel) {}
            } message: {
                Text("iPhone 没有心率传感器。在手表上开个体能训练，心率会经苹果健康实时显示。")
            }
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
