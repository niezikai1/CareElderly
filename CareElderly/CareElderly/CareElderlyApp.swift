// CareElderlyApp.swift
// Designed by Zackary Nie(聂子开)
// App entry point: creates and injects global ViewModels, wires Combine pipelines
// between VitalSignViewModel and AppState, and configures global UIKit appearance.

import SwiftUI
import UIKit
import Combine
import UserNotifications

@main
struct CareElderlyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Globally Shared State Objects
    @StateObject private var authViewModel  = AuthViewModel()
    @StateObject private var appState       = AppState()
    @StateObject private var vitalViewModel = VitalSignViewModel()

    // MARK: - Init
    init() {
        configureGlobalAppearance()
    }

    // MARK: - Scene
    var body: some Scene {
        WindowGroup {
            SplashView()
                .preferredColorScheme(.light)
                .environment(\.managedObjectContext, PersistenceController.shared.context)
                .environmentObject(authViewModel)
                .environmentObject(appState)
                .environmentObject(vitalViewModel)

                // ── Wire VitalSignViewModel → AppState ────────────────────
                // Forward MQTT connection status to AppState so the
                // banner in DashboardView and SettingsView updates correctly.
                .onReceive(
                    vitalViewModel.mqttService.$connectionStatus
                ) { status in
                    appState.connectionStatus = status
                }

                // ── Forward incoming alert events → AppState ──────────────
                // When the backend sends an alert, if the current user is a
                // guardian, trigger the strong-alert popup + vibration + push.
                .onReceive(
                    vitalViewModel.$pendingAlertEvent.compactMap { $0 }
                ) { event in
                    if authViewModel.isGuardian {
                        appState.triggerGuardianAlert(event: event)
                    }
                    // Reset so the same event isn't re-processed
                    vitalViewModel.pendingAlertEvent = nil
                }

                // ── Auto-connect on login ─────────────────────────────────
                // After a successful login, attempt to connect to the last
                // saved server URL (if any).
                .onReceive(
                    authViewModel.$isLoggedIn
                ) { isLoggedIn in
                    guard isLoggedIn else {
                        vitalViewModel.reset()
                        return
                    }
                    // Configure notification permissions based on role
                    appState.configure(for: authViewModel.currentRole)

                    // Connect to saved broker (no-op if host not yet configured)
                    vitalViewModel.connectFromSavedSettings()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    appState.handleScenePhaseChange(newPhase)
                }
        }
    }

    // MARK: - Global UI Appearance
    private func configureGlobalAppearance() {
        // Tab bar: opaque, system-background fill
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = UIColor.systemBackground
        UITabBar.appearance().standardAppearance   = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar

        // Navigation bar: opaque, no shadow/separator line
        let navBar = UINavigationBarAppearance()
        navBar.configureWithOpaqueBackground()
        navBar.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance     = navBar
        UINavigationBar.appearance().scrollEdgeAppearance   = navBar
        UINavigationBar.appearance().compactAppearance      = navBar
    }
}
