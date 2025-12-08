//
//  OnboardingFlowView.swift
//  Rockout
//
//  5-screen video-based onboarding flow.
//  App entry point: RockOutApp.swift → RootAppView
//  Auth flow: Uses AuthViewModel with authState (.loading, .unauthenticated, .authenticated, .passwordReset)
//  After onboarding: Shows AuthFlowView if unauthenticated, MainTabView if authenticated
//

import SwiftUI

struct OnboardingFlowView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentIndex: Int = 0
    
    let totalScreens = 5
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            TabView(selection: $currentIndex) {
                // Screen 0: Welcome
                OnboardingVideoScreen(
                    videoName: "welcome_onboarding2",
                    title: "WELCOME TO ROCKOUT",
                    subtitle: "For people who live inside their music.",
                    description: "RockOut turns your listening habits, favorite artists, and creative expression into a shared experience built around music.",
                    bottomMaskFraction: 0.20,
                    videoScale: 1.0,  // Fill screen
                    contentBottomPadding: 50,  // Standard padding
                    onContinue: {
                        withAnimation {
                            currentIndex = 1
                        }
                    },
                    showSkip: true,
                    onSkip: {
                        // Skip to end
                        hasCompletedOnboarding = true
                    }
                )
                .tag(0)
                
                // Screen 1: GreenRoom
                OnboardingVideoScreen(
                    videoName: "greenroom_onboarding2",
                    title: "GreenRoom",
                    subtitle: "Drop Bars & Join the Culture",
                    description: "We are all artists here...Share Bars as photos, videos, text, polls, or voice notes. Explore hashtags like #BarOfTheDay and feel the rooms energy.",
                    bottomMaskFraction: 0.20,
                    videoScale: 1.0,  // Fill screen
                    contentBottomPadding: 50,  // Standard padding
                    onContinue: {
                        withAnimation {
                            currentIndex = 2
                        }
                    },
                    showSkip: true,
                    onSkip: {
                        hasCompletedOnboarding = true
                    }
                )
                .tag(1)
                
                // Screen 2: SoundPrint
                OnboardingVideoScreen(
                    videoName: "soundprint_onboarding",
                    title: "SOUNDPRINT",
                    subtitle: "Your Musical Scorecard",
                    description: "See your listening habits visualized as a living musical fingerprint. Track how your sound evolves over time.",
                    bottomMaskFraction: 0.20,
                    videoScale: 1.0,  // Fill screen
                    contentBottomPadding: 50,  // Standard padding
                    onContinue: {
                        withAnimation {
                            currentIndex = 3
                        }
                    },
                    showSkip: true,
                    onSkip: {
                        hasCompletedOnboarding = true
                    }
                )
                .tag(2)
                
                // Screen 3: RockList
                OnboardingVideoScreen(
                    videoName: "rocklist_onboarding2",
                    title: "ROCKLIST",
                    subtitle: "The Listener Leaderboard",
                    description: "Climb the RockList by being a top listener for your favorite artists. Turn your devotion into visible rank.",
                    bottomMaskFraction: 0.20,
                    videoScale: 1.0,  // Fill screen
                    contentBottomPadding: 50,  // Standard padding
                    onContinue: {
                        withAnimation {
                            currentIndex = 4
                        }
                    },
                    showSkip: true,
                    onSkip: {
                        hasCompletedOnboarding = true
                    }
                )
                .tag(3)
                
                // Screen 4: StudioSessions
                OnboardingVideoScreen(
                    videoName: "studiosessions_onboarding",
                    title: "STUDIOSESSIONS",
                    subtitle: "Private Uploads & Collabs",
                    description: "Unlock exclusive artist drops and collaborate in shared creative spaces. StudioSessions is where new sounds are born.",
                    bottomMaskFraction: 0.20,
                    videoScale: 1.0,  // Keep normal scale for StudioSessions
                    contentBottomPadding: 50,  // Default padding
                    onContinue: {
                        // Complete onboarding and navigate to auth/main app
                        hasCompletedOnboarding = true
                    },
                    showSkip: false,
                    onSkip: {}
                )
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
    }
}
