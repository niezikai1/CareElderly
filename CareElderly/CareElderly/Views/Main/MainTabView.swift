// Views/Main/MainTabView.swift
// Main TabView: four tabs, guardian-only badge and role badge overlay

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var authViewModel:  AuthViewModel
    @EnvironmentObject var appState:        AppState
    @EnvironmentObject var vitalViewModel: VitalSignViewModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $appState.selectedTab) {

                // Tab 0: Live Monitor (all roles)
                DashboardView()
                    .tabItem { Label("Monitor", systemImage: "waveform.path.ecg") }
                    .tag(0)

                // Tab 1: History (all roles)
                HistoryView()
                    .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                    .tag(1)

                if authViewModel.isGuardian {
                    // Tab 2: Health Insights — guardian only
                    AnalyticsView()
                        .tabItem { Label("Insights", systemImage: "brain.head.profile") }
                        .tag(2)

                    // Tab 3: Alert Center — guardian only
                    AlertsView()
                        .tabItem { Label("Alerts", systemImage: "bell.badge.fill") }
                        .badge(appState.unreadAlertCount)
                        .tag(3)

                    // Tab 4: Settings
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(4)
                } else {
                    // Tab 2: Settings (patient — no Insights / Alerts)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                        .tag(2)
                }
            }
            .tint(Color(hex: "1976D2"))

            // Role badge in top-right corner (always visible)
            if let user = authViewModel.currentUser {
                RoleBadge(user: user)
                    .padding(.top, 56)  // Clear Dynamic Island / notch
                    .padding(.trailing, 16)
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
        // Guardian strong-alert popup overlay
        .overlay {
            if authViewModel.isGuardian, appState.showAlertPopup,
               let event = appState.activeAlertEvent {
                GuardianAlertPopup(event: event) {
                    appState.acknowledgeAlert()
                }
                .zIndex(100)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: appState.showAlertPopup)
            }
        }
    }


}

// MARK: - Guardian Strong Alert Popup
struct GuardianAlertPopup: View {
    let event: AlertEvent
    let onAcknowledge: () -> Void

    @State private var pulse = false

    var body: some View {
        ZStack {
            // Semi-transparent overlay — intercepts taps to prevent accidental dismissal
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {}

            VStack(spacing: 0) {
                // Top danger indicator bar
                Rectangle()
                    .fill(event.type.isCritical ? Color(hex: "B71C1C") : Color(hex: "E65100"))
                    .frame(height: 6)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 20) {
                    // Icon + title
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: event.type.severity.colorHex).opacity(0.15))
                                .frame(width: 80, height: 80)
                                .scaleEffect(pulse ? 1.15 : 1.0)
                                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)

                            Image(systemName: event.type.icon)
                                .font(.system(size: 36))
                                .foregroundColor(Color(hex: event.type.severity.colorHex))
                        }

                        Text(event.type.isCritical ? "🚨 CRITICAL ALERT" : "⚠️ ABNORMAL WARNING")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: event.type.severity.colorHex))
                            .textCase(.uppercase)

                        Text(event.type.displayName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.primary)

                        Text(event.formattedDateTime)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }

                    // Vital data chips (if available)
                    if event.heartRate != nil || event.breathingRate != nil {
                        HStack(spacing: 20) {
                            if let hr = event.heartRate {
                                vitalChip(icon: "heart.fill", value: "\(Int(hr))", unit: "bpm", color: "E53935")
                            }
                            if let br = event.breathingRate {
                                vitalChip(icon: "lungs.fill", value: String(format: "%.1f", br), unit: "rpm", color: "1976D2")
                            }
                        }
                    }

                    // Care advice
                    Text(event.type.advice)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)

                    // Emergency call + acknowledge buttons
                    VStack(spacing: 12) {
                        EmergencyCallButton()

                        Button(action: onAcknowledge) {
                            Text("Acknowledged — Handle Now")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(Color(hex: "1976D2"))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(hex: "E3F2FD"))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 10)
            .padding(.horizontal, 20)
        }
        .onAppear { pulse = true }
    }

    private func vitalChip(icon: String, value: String, unit: String, color: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: color))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.primary)
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(hex: color).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    MainTabView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppState())
}
