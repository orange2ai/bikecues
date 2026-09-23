import SwiftUI

@main
struct BikeCuesApp: App {
    @StateObject private var engine = RideEngine.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
                .onAppear {
                    // 调试用：-autoRide 启动即开骑，方便无人值守验证定位链路
                    if CommandLine.arguments.contains("-autoRide") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { engine.startRide() }
                    }
                }
        }
    }
}
