// Views/Auth/SplashView.swift
// Launch screen: shows logo animation, then routes based on login state

import SwiftUI

struct SplashView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState

    @State private var logoScale:   CGFloat = 0.6
    @State private var logoOpacity: Double  = 0
    @State private var showContent  = false

    var body: some View {
        ZStack {
            if showContent {
                Group {
                    if authViewModel.isLoggedIn {
                        MainTabView()
                    } else {
                        LoginView()
                    }
                }
                .transition(.opacity)
            } else {
                splashScreen
            }
        }
        .animation(.easeInOut(duration: 0.45), value: showContent)
        .animation(.easeInOut(duration: 0.45), value: authViewModel.isLoggedIn)
    }

    // MARK: - Launch animation
    var splashScreen: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "0A3D8F"), Color(hex: "1565C0"), Color(hex: "1976D2")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle().fill(Color.white.opacity(0.06)).frame(width: 320, height: 320).offset(x: 130, y: -200)
            Circle().fill(Color.white.opacity(0.05)).frame(width: 220, height: 220).offset(x: -100, y: 250)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle().fill(Color.white.opacity(0.15)).frame(width: 120, height: 120)
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 58)).foregroundColor(.white)
                }
                .scaleEffect(logoScale).opacity(logoOpacity)

                VStack(spacing: 8) {
                    Text("CareElderly")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("AI-Powered Vital Sign Monitor")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.white)
                        .tracking(0.5)
                    Text("Developed by Zackary Zikai Nie")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                }
                .padding(.top, 24).opacity(logoOpacity)

                Spacer()

                VStack(spacing: 4) {
                    Text("Xidian University · School of AI")
                        .font(.caption).foregroundColor(.white.opacity(0.55))
                    Text("Final Year Project · Class of 2026")
                        .font(.caption2).foregroundColor(.white.opacity(0.4))
                }
                .padding(.bottom, 50).opacity(logoOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) {
                logoScale   = 1.0
                logoOpacity = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation { showContent = true }
            }
        }
    }
}

#Preview {
    SplashView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppState())
        .environmentObject(VitalSignViewModel())
}
