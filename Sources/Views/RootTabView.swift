import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var engine: RideEngine

    var body: some View {
        TabView {
            RideView()
                .tabItem { Label("骑行", systemImage: "bicycle") }
            CuesView()
                .tabItem { Label("播报", systemImage: "speaker.wave.2") }
            LogView()
                .tabItem { Label("记录", systemImage: "book.closed") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.orange)
    }
}
