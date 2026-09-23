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
                    // 调试用：-autoRide 启动即开骑，-autoEnd 65 秒后自动结束（方便无人值守看结算页）
                    if CommandLine.arguments.contains("-autoRide") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { engine.startRide() }
                    }
                    if CommandLine.arguments.contains("-autoEnd") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 68) { engine.endRide() }
                    }
                    if CommandLine.arguments.contains("-fakeSummary") {
                        engine.state.distanceKm = 12.48
                        engine.state.elapsed = 2452
                        engine.state.averageSpeedKmh = 18.3
                        engine.state.maxSpeedKmh = 34.6
                        engine.state.calories = 412
                        engine.showSummary = true
                    }
                }
        }
    }
}
