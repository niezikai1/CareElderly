// Views/Main/SettingsView.swift
// Settings screen: account info, MQTT connection config, alert thresholds (guardian-only),
// app info, and sign out.

import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var authViewModel:  AuthViewModel
    @EnvironmentObject var appState:        AppState
    @EnvironmentObject var vitalViewModel: VitalSignViewModel

    @State private var showLogoutAlert        = false
    @State private var showDeleteAccountAlert = false
    @State private var showDemoBlockedAlert   = false

    var body: some View {
        NavigationStack {
            List {
                userInfoSection
                if authViewModel.isGuardian { guardianNotificationSection }
                connectionSection
                dataManagementSection
                appInfoSection

                // Sign out
                Section {
                    Button(role: .destructive) {
                        showLogoutAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                }

                // Delete account
                Section {
                    Button(role: .destructive) {
                        showDeleteAccountAlert = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Account", systemImage: "person.crop.circle.badge.minus")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                } footer: {
                    Text("Permanently deletes your account and signs you out. This cannot be undone.")
                        .font(.system(size: 12))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        }
        .alert("Sign Out?", isPresented: $showLogoutAlert) {
            Button("Sign Out", role: .destructive) {
                vitalViewModel.disconnect()
                authViewModel.logout()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to sign in again to view monitoring data.")
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountAlert) {
            Button("Delete Account", role: .destructive) {
                vitalViewModel.reset()
                let deleted = authViewModel.deleteAccount()
                if !deleted { showDemoBlockedAlert = true }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be permanently removed. You will be signed out immediately and cannot sign back in with these credentials.")
        }
        .alert("Cannot Delete Demo Account", isPresented: $showDemoBlockedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Built-in demo accounts cannot be deleted.")
        }
    }

    // MARK: - User Info Section
    var userInfoSection: some View {
        Section {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [Color(hex: authViewModel.currentRole.colorHex),
                                     Color(hex: authViewModel.currentRole.colorHex).opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                    Image(systemName: authViewModel.currentRole.icon)
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(authViewModel.currentUser?.displayName ?? "—")
                        .font(.system(size: 18, weight: .semibold))
                    Text(authViewModel.currentUser?.role.displayName ?? "—")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: authViewModel.currentRole.colorHex))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(authViewModel.currentRole == .guardian
                            ? Color(.systemBlue).opacity(0.12)
                            : Color(.systemGreen).opacity(0.12))
                        .clipShape(Capsule())
                    Text("@\(authViewModel.currentUser?.username ?? "")")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    // MARK: - Guardian Notification Section
    var guardianNotificationSection: some View {
        Section("Notifications & Alerts (Guardian Only)") {
            HStack {
                Label("Push Notifications", systemImage: "bell.badge.fill")
                Spacer()
                if appState.notificationsEnabled {
                    Label("Enabled", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13)).foregroundColor(.green)
                        .labelStyle(.titleAndIcon)
                } else {
                    Button("Enable in Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.system(size: 13)).foregroundColor(.orange)
                }
            }
            HStack {
                Label("Alert Style", systemImage: "speaker.wave.3.fill")
                Spacer()
                Text("Vibration + Sound + Popup")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            }
            HStack {
                Label("Critical Repeat Interval", systemImage: "clock.badge.exclamationmark")
                Spacer()
                Text("Every 30 s")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            }
            NavigationLink {
                ThresholdSettingsView()
            } label: {
                Label("Alert Thresholds", systemImage: "slider.horizontal.3")
            }
        }
    }

    // MARK: - Connection Section
    var connectionSection: some View {
        Section("Backend Connection") {
            // Status row
            HStack {
                Label("Status", systemImage: "wifi")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: appState.connectionStatus.colorHex))
                        .frame(width: 8, height: 8)
                    Text(shortStatus)
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: appState.connectionStatus.colorHex))
                }
            }

            // Broker address config
            NavigationLink {
                ServerConfigView()
                    .environmentObject(vitalViewModel)
                    .environmentObject(appState)
            } label: {
                HStack {
                    Label("Broker Address", systemImage: "server.rack")
                    Spacer()
                    Text(savedHost.isEmpty ? "Not configured" : savedHost)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            // Quick connect / disconnect toggle
            if appState.connectionStatus.isConnected {
                Button(role: .destructive) {
                    vitalViewModel.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "wifi.slash")
                        .foregroundColor(.red)
                }
            } else if !savedHost.isEmpty {
                Button {
                    vitalViewModel.connectFromSavedSettings()
                } label: {
                    Label("Connect Now", systemImage: "wifi")
                        .foregroundColor(Color(hex: "1976D2"))
                }
            }
        }
    }

    // MARK: - Data Management Section
    var dataManagementSection: some View {
        Section("Data Management") {
            NavigationLink {
                DataCleanupView()
            } label: {
                Label("Clear Old Records", systemImage: "trash.slash.fill")
            }
        }
    }

    // MARK: - App Info Section
    var appInfoSection: some View {
        Section("About") {
            infoRow(label: "App Version",      value: "1.0.0 (2026)",              icon: "info.circle")
            infoRow(label: "Graduation Project", value: "Xidian University · 2026", icon: "graduationcap.fill")
            infoRow(label: "Supervisor",        value: "Hui Zhao",                  icon: "person.badge.key.fill")
            HStack {
                Text("Designed By Zackary Zikai Nie")
                    .font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
    }

    private func infoRow(label: String, value: String, icon: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value).font(.system(size: 13)).foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers
    private var savedHost: String {
        UserDefaults.standard.string(forKey: "mqttHost") ?? ""
    }

    private var shortStatus: String {
        switch appState.connectionStatus {
        case .connected:    return "Connected"
        case .connecting:   return "Connecting…"
        case .disconnected: return "Disconnected"
        case .error:        return "Error"
        }
    }
}

// MARK: - Server Configuration Sub-Page
struct ServerConfigView: View {
    @EnvironmentObject var vitalViewModel: VitalSignViewModel
    @EnvironmentObject var appState:        AppState
    @Environment(\.dismiss) private var dismiss

    @State private var hostText:  String = UserDefaults.standard.string(forKey: "mqttHost")     ?? ""
    @State private var portText:  String = {
        let p = UserDefaults.standard.integer(forKey: "mqttPort")
        return p > 0 ? "\(p)" : "1883"
    }()
    @State private var topicText:    String = UserDefaults.standard.string(forKey: "mqttTopic")    ?? "vitals"
    @State private var usernameText: String = UserDefaults.standard.string(forKey: "mqttUsername") ?? ""
    @State private var passwordText: String = UserDefaults.standard.string(forKey: "mqttPassword") ?? ""
    @State private var useTLS:       Bool   = UserDefaults.standard.bool(forKey: "mqttUseTLS")
    @State private var showSavedBanner = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "server.rack")
                        .foregroundColor(Color(hex: "1976D2"))
                    TextField("192.168.1.100", text: $hostText)
                        .keyboardType(.numbersAndPunctuation)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, design: .monospaced))
                }
                HStack {
                    Image(systemName: "number")
                        .foregroundColor(Color(hex: "1976D2"))
                    TextField("1883", text: $portText)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14, design: .monospaced))
                }
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundColor(Color(hex: "1976D2"))
                    TextField("vitals", text: $topicText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, design: .monospaced))
                }
                Toggle(isOn: $useTLS) {
                    Label("TLS / SSL (mqtts://)", systemImage: "lock.fill")
                }
                .tint(Color(hex: "1976D2"))
            } header: {
                Text("MQTT Broker")
            } footer: {
                Text("Use port 8883 with TLS enabled for cloud brokers (e.g. EMQX Cloud). Use port 1883 without TLS for local brokers.")
                    .font(.system(size: 12))
            }

            Section {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(Color(hex: "1976D2"))
                    TextField("Username (optional)", text: $usernameText)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .font(.system(size: 14, design: .monospaced))
                }
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundColor(Color(hex: "1976D2"))
                    SecureField("Password (optional)", text: $passwordText)
                        .font(.system(size: 14, design: .monospaced))
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Leave blank if the broker does not require credentials.")
                    .font(.system(size: 12))
            }

            Section {
                Button {
                    saveAndConnect()
                } label: {
                    HStack {
                        Spacer()
                        Label(
                            appState.connectionStatus.isConnected ? "Reconnect" : "Save & Connect",
                            systemImage: "wifi"
                        )
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        Spacer()
                    }
                }
                .listRowBackground(Color(hex: "1976D2"))

                if appState.connectionStatus.isConnected {
                    Button(role: .destructive) {
                        vitalViewModel.disconnect()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Disconnect", systemImage: "wifi.slash")
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                        }
                    }
                }
            }

            Section("Connection Status") {
                HStack {
                    Circle()
                        .fill(Color(hex: appState.connectionStatus.colorHex))
                        .frame(width: 10, height: 10)
                    Text(appState.connectionStatus.displayText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }

            Section("Message Format (JSON)") {
                VStack(alignment: .leading, spacing: 8) {
                    protocolRow(type: "vitals",  desc: "heart_rate_bpm · respiratory_rate_rpm · body_temperature_celsius · timestamp_ms")
                    protocolRow(type: "alert",   desc: "type=alert · event_type · heart_rate_bpm · respiratory_rate_rpm")
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("MQTT Config")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .top) {
            if showSavedBanner {
                Text("✓ Saved & connecting…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(hex: "2E7D32"))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showSavedBanner)
    }

    private func saveAndConnect() {
        let host     = hostText.trimmingCharacters(in: .whitespacesAndNewlines)
        let port     = UInt16(portText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1883
        let topic    = topicText.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = usernameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        let ud = UserDefaults.standard
        ud.set(host,      forKey: "mqttHost")
        ud.set(Int(port), forKey: "mqttPort")
        ud.set(topic,     forKey: "mqttTopic")
        ud.set(username,  forKey: "mqttUsername")
        ud.set(password,  forKey: "mqttPassword")
        ud.set(useTLS,    forKey: "mqttUseTLS")
        vitalViewModel.connect(host: host, port: port, topic: topic,
                               username: username, password: password, useTLS: useTLS)
        showSavedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showSavedBanner = false }
    }

    private func protocolRow(type: String, desc: String) -> some View {
        HStack(spacing: 10) {
            Text(type)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(hex: "1976D2"))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color(.systemBlue).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            Text(desc)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Alert Threshold Settings Sub-Page
struct ThresholdSettingsView: View {

    // Heart rate thresholds (stored in UserDefaults)
    @AppStorage("hrWarningLow")  private var hrWarningLow:  Double = 50
    @AppStorage("hrWarningHigh") private var hrWarningHigh: Double = 100
    @AppStorage("hrCriticalLow") private var hrCriticalLow: Double = 40
    @AppStorage("hrCriticalHigh") private var hrCriticalHigh: Double = 120

    // Breathing rate thresholds
    @AppStorage("brWarningLow")  private var brWarningLow:  Double = 12
    @AppStorage("brWarningHigh") private var brWarningHigh: Double = 20
    @AppStorage("brCriticalLow") private var brCriticalLow: Double = 8
    @AppStorage("brCriticalHigh") private var brCriticalHigh: Double = 25

    var body: some View {
        Form {
            Section("Heart Rate Thresholds (bpm)") {
                thresholdRow(label: "Warning Low",   value: $hrWarningLow,   range: 30...60)
                thresholdRow(label: "Warning High",  value: $hrWarningHigh,  range: 80...140)
                thresholdRow(label: "Critical Low",  value: $hrCriticalLow,  range: 20...50)
                thresholdRow(label: "Critical High", value: $hrCriticalHigh, range: 100...160)
            }

            Section("Breathing Rate Thresholds (rpm)") {
                thresholdRow(label: "Warning Low",   value: $brWarningLow,   range: 8...15)
                thresholdRow(label: "Warning High",  value: $brWarningHigh,  range: 16...25)
                thresholdRow(label: "Critical Low",  value: $brCriticalLow,  range: 4...12)
                thresholdRow(label: "Critical High", value: $brCriticalHigh, range: 20...35)
            }

            Section {
                Button("Restore Defaults") { resetDefaults() }
                    .foregroundColor(.orange)
            }
        }
        .navigationTitle("Alert Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thresholdRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Stepper(value: value, in: range, step: 1) {
                Text(String(format: "%.0f", value.wrappedValue))
                    .frame(width: 40, alignment: .trailing)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
        }
    }

    private func resetDefaults() {
        hrWarningLow = 50;  hrWarningHigh = 100
        hrCriticalLow = 40; hrCriticalHigh = 120
        brWarningLow = 12;  brWarningHigh = 20
        brCriticalLow = 8;  brCriticalHigh = 25
    }
}

// MARK: - Data Cleanup Sub-Page
struct DataCleanupView: View {
    @State private var showConfirm    = false
    @State private var showConfirmAll = false
    @State private var deletedBanner  = false
    @State private var selectedAge: Int = 30

    private let ageOptions = [7, 14, 30, 60, 90]

    var body: some View {
        Form {
            Section("Delete Records Older Than") {
                Picker("Age", selection: $selectedAge) {
                    ForEach(ageOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Delete Old Records", systemImage: "trash.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                }
            } footer: {
                Text("Permanently removes vital-sign and alert records older than the selected period.")
                    .font(.system(size: 12))
            }

            Section {
                Button(role: .destructive) {
                    showConfirmAll = true
                } label: {
                    HStack {
                        Spacer()
                        Label("Clear ALL Records", systemImage: "trash.slash.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Spacer()
                    }
                }
            } footer: {
                Text("Wipes every vital-sign and alert record from local storage. Useful for resetting test data.")
                    .font(.system(size: 12))
            }
        }
        .navigationTitle("Clear Old Records")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Confirm Delete", isPresented: $showConfirm) {
            Button("Delete", role: .destructive) { deleteOldRecords() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete all records older than \(selectedAge) days? This cannot be undone.")
        }
        .alert("Clear ALL Records?", isPresented: $showConfirmAll) {
            Button("Clear All", role: .destructive) { deleteAllRecords() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete every vital-sign and alert record. Cannot be undone.")
        }
        .overlay(alignment: .top) {
            if deletedBanner {
                Text("✓ Old records deleted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .background(Color(hex: "2E7D32"))
                    .clipShape(Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: deletedBanner)
    }

    private func deleteOldRecords() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -selectedAge, to: Date())!
        PersistenceController.shared.deleteRecordsOlderThan(cutoff)
        showBanner()
    }

    private func deleteAllRecords() {
        PersistenceController.shared.deleteAllRecords()
        showBanner()
    }

    private func showBanner() {
        deletedBanner = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { deletedBanner = false }
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppState())
        .environmentObject(VitalSignViewModel())
}
