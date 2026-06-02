// Views/Main/AlertsView.swift
// Alert Center: both roles can view, but patients see a read-only banner

import SwiftUI

struct AlertsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState

    @FetchRequest(fetchRequest: AlertRecord.fetchPending(), animation: .default)
    private var pendingRecords: FetchedResults<AlertRecord>

    @FetchRequest(fetchRequest: AlertRecord.fetchHandled(), animation: .default)
    private var handledRecords: FetchedResults<AlertRecord>

    var body: some View {
        NavigationStack {
            Group {
                if pendingRecords.isEmpty && handledRecords.isEmpty {
                    emptyState
                } else {
                    alertList
                }
            }
            .navigationTitle("Alert Center")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if authViewModel.isGuardian && !pendingRecords.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Mark All Read") {
                            withAnimation {
                                for record in pendingRecords {
                                    record.isAcknowledged = true
                                    record.acknowledgedAt = Date()
                                }
                                PersistenceController.shared.save()
                                appState.unreadAlertCount = 0
                            }
                        }
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "1976D2"))
                    }
                }
            }
        }
    }

    // MARK: - Alert List
    var alertList: some View {
        List {
            if !authViewModel.isGuardian {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(Color(hex: "2E7D32"))
                        Text("You are viewing alerts as a patient. You will not receive push notifications.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(Color(.systemGreen).opacity(0.12))
                }
            }

            if !pendingRecords.isEmpty {
                Section("Pending (\(pendingRecords.count))") {
                    ForEach(pendingRecords) { record in
                        if let event = record.toAlertEvent {
                            AlertRow(event: event, onAcknowledge: { acknowledgeRecord(record) })
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color(hex: event.type.severity.colorHex).opacity(0.05))
                        }
                    }
                }
            }

            if !handledRecords.isEmpty {
                Section("Handled (\(handledRecords.count))") {
                    ForEach(handledRecords) { record in
                        if let event = record.toAlertEvent {
                            AlertRow(event: event, onAcknowledge: nil)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                .opacity(0.65)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
    }

    // MARK: - Empty State
    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 60))
                .foregroundColor(Color(hex: "2E7D32").opacity(0.4))
            Text("No Alerts")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text("The patient's vitals look normal — all clear.")
                .font(.callout)
                .foregroundColor(.secondary.opacity(0.7))
            Spacer()
        }
    }

    // MARK: - Acknowledge
    private func acknowledgeRecord(_ record: AlertRecord) {
        withAnimation {
            record.isAcknowledged = true
            record.acknowledgedAt = Date()
            PersistenceController.shared.save()
            if appState.unreadAlertCount > 0 { appState.unreadAlertCount -= 1 }
        }
    }
}

// MARK: - Single Alert Row
struct AlertRow: View {
    let event: AlertEvent
    let onAcknowledge: (() -> Void)?  // nil = read-only mode (already handled / patient)

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color(hex: event.type.severity.colorHex).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: event.type.icon)
                    .font(.system(size: 20))
                    .foregroundColor(Color(hex: event.type.severity.colorHex))
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(event.type.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(event.formattedTime)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Text(event.formattedDate)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                // Vital data row
                if event.heartRate != nil || event.breathingRate != nil {
                    HStack(spacing: 10) {
                        if let hr = event.heartRate {
                            Label("\(Int(hr)) bpm", systemImage: "heart.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "E53935"))
                        }
                        if let br = event.breathingRate {
                            Label(String(format: "%.1f rpm", br), systemImage: "lungs.fill")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "1976D2"))
                        }
                    }
                }
            }

            // Acknowledge button (guardian + unacknowledged only)
            if let action = onAcknowledge {
                Button(action: action) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(hex: "2E7D32"))
                }
                .buttonStyle(.borderless)
            } else if event.isAcknowledged {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green.opacity(0.5))
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AlertsView()
        .environment(\.managedObjectContext, PersistenceController.preview.context)
        .environmentObject(AuthViewModel())
        .environmentObject(AppState())
}
