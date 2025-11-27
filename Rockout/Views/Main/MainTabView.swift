import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showFeed = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main TabView with 4 tabs (Feed is separate)
            TabView(selection: $selectedTab) {
                SoundPrintView()
                    .tag(0)
                    .tabItem {
                        Label("SoundPrint", systemImage: "waveform")
                    }
                
                StudioSessionsView()
                    .tag(1)
                    .tabItem {
                        Label("Studiosessions", systemImage: "music.note.list")
                    }
                
                MyRockListView()
                    .tag(2)
                    .tabItem {
                        Label("My RockList", systemImage: "list.number")
                    }
                
                ProfileView()
                    .tag(3)
                    .tabItem {
                        Label("Profile", systemImage: "person.crop.circle")
                    }
            }
            
            // Floating Feed Button (centered)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Button {
                        showFeed = true
                    } label: {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue, Color.purple],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                            )
                    }
                    .offset(y: -34) // Elevated above tab bar
                    
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showFeed) {
            NavigationStack {
                FeedView()
                    .navigationTitle("Feed")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showFeed = false
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
            }
        }
    }
}
