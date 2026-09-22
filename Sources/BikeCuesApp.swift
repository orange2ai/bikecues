import SwiftUI

@main
struct BikeCuesApp: App {
    @StateObject private var engine = RideEngine.shared

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(engine)
                .preferredColorScheme(.dark)
        }
    }
}
