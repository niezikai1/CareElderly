// Views/Main/HistoryView.swift
// Full history screen backed by Core Data.
//
// Features:
//   • Date range filter: Today / 7 Days / 30 Days / All Time
//   • Tab toggle: Vital Signs list vs. Alert Events list
//   • Statistics summary card (avg HR, avg BR, alert count)
//   • Daily trend bar chart using Swift Charts
//   • Scrollable record list with status colour coding

import SwiftUI
import Charts

struct HistoryView: View {

    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // ── Date range filter ────────────────────────────────────
                    dateFilterBar
                        .padding(.horizontal, 16)

                    // ── Statistics summary card ──────────────────────────────
                    statsSummaryCard
                        .padding(.horizontal, 16)

                    // ── Daily trend chart ────────────────────────────────────
                    if !vm.dailyAggregates.isEmpty {
                        dailyTrendChart
                            .padding(.horizontal, 16)
                    }

                    // ── Content tab picker ───────────────────────────────────
                    Picker("Content", selection: $vm.selectedTab) {
                        ForEach(HistoryTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    // ── Record list ──────────────────────────────────────────
                    if vm.selectedTab == .vitals {
                        vitalRecordsList
                    } else {
                        alertRecordsList
                    }

                    Spacer(minLength: 24)
                }
                .padding(.top, 12)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        vm.fetch()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
    }

    // MARK: - Date Filter Bar
    var dateFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DateRangeFilter.allCases) { filter in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.dateFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                vm.dateFilter == filter
                                    ? Color(hex: "1976D2")
                                    : Color(.secondarySystemBackground)
                            )
                            .foregroundColor(
                                vm.dateFilter == filter ? .white : .primary
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Statistics Summary Card
    var statsSummaryCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                statCell(
                    label: "Avg Heart Rate",
                    value: vm.avgHeartRate.map { String(format: "%.0f", $0) } ?? "—",
                    unit:  "bpm",
                    icon:  "heart.fill",
                    color: "E53935"
                )
                Divider().frame(height: 48)
                statCell(
                    label: "Avg Breathing",
                    value: vm.avgBreathingRate.map { String(format: "%.1f", $0) } ?? "—",
                    unit:  "rpm",
                    icon:  "lungs.fill",
                    color: "1976D2"
                )
                Divider().frame(height: 48)
                statCell(
                    label: "Total Alerts",
                    value: "\(vm.totalAlertCount)",
                    unit:  vm.criticalCount > 0 ? "\(vm.criticalCount) critical" : "events",
                    icon:  "bell.fill",
                    color: vm.criticalCount > 0 ? "D32F2F" : "FF8F00"
                )
            }
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func statCell(label: String, value: String, unit: String,
                          icon: String, color: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(hex: color))
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: color))
            Text(unit)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Daily Trend Chart
    var dailyTrendChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily Average Trend")
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 16)

            Chart(vm.dailyAggregates) { day in
                // Heart rate bar
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("HR",   day.avgHeartRate),
                    width: .ratio(0.35)
                )
                .foregroundStyle(Color(hex: "E53935").opacity(0.8))
                .position(by: .value("Type", "HR"), axis: .horizontal)
                .annotation(position: .top) {
                    Text(String(format: "%.0f", day.avgHeartRate))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }

                // Breathing rate bar
                BarMark(
                    x: .value("Date", day.date, unit: .day),
                    y: .value("BR",   day.avgBreathingRate),
                    width: .ratio(0.35)
                )
                .foregroundStyle(Color(hex: "1976D2").opacity(0.8))
                .position(by: .value("Type", "BR"), axis: .horizontal)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(
                        format: vm.dateFilter == .today ? .dateTime.hour() : .dateTime.month().day()
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
            .chartLegend(position: .bottom, alignment: .leading) {
                HStack(spacing: 16) {
                    legendDot(color: "E53935", label: "Heart Rate (bpm)")
                    legendDot(color: "1976D2", label: "Breathing (rpm)")
                }
                .font(.system(size: 11))
                .padding(.top, 4)
            }
            .frame(height: 160)
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func legendDot(color: String, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
            Text(label).foregroundColor(.secondary)
        }
    }

    // MARK: - Vital Records List
    @ViewBuilder
    var vitalRecordsList: some View {
        if vm.vitalRecords.isEmpty {
            emptyState(
                icon: "waveform.path.ecg",
                message: "No vital sign records in this period.\nData is saved while the monitor is running."
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(vm.vitalRecords.prefix(200)) { data in
                    VitalHistoryRow(data: data)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Alert Records List
    @ViewBuilder
    var alertRecordsList: some View {
        if vm.alertRecords.isEmpty {
            emptyState(
                icon: "bell.slash",
                message: "No alerts in this period.\nAll clear!"
            )
        } else {
            LazyVStack(spacing: 8) {
                ForEach(vm.alertRecords) { event in
                    AlertHistoryRow(event: event) {
                        vm.acknowledge(event: event)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Empty State
    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "1976D2").opacity(0.3))
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary.opacity(0.75))
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Vital History Row
private struct VitalHistoryRow: View {
    let data: VitalSignData

    var body: some View {
        HStack(spacing: 12) {

            // Timestamp
            VStack(alignment: .leading, spacing: 2) {
                Text(data.formattedTime)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.primary)
                Text(dateString)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .frame(width: 72, alignment: .leading)

            Divider().frame(height: 36)

            // Heart rate
            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "E53935"))
                Text(data.heartRateText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: data.heartRateStatus.colorHex))
                Text("bpm")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Divider().frame(height: 36)

            // Breathing rate
            HStack(spacing: 4) {
                Image(systemName: "lungs.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "1976D2"))
                Text(data.breathingRateText)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: data.breathingRateStatus.colorHex))
                Text("rpm")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Overall status badge (only if not normal)
            if data.heartRateStatus != .normal || data.breathingRateStatus != .normal {
                let worst = data.heartRateStatus == .critical || data.breathingRateStatus == .critical
                    ? VitalStatus.critical : VitalStatus.warning
                Image(systemName: worst.sfSymbol)
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: worst.colorHex))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return fmt.string(from: data.timestamp)
    }
}

// MARK: - Alert History Row
private struct AlertHistoryRow: View {
    let event: AlertEvent
    let onAcknowledge: () -> Void

    var body: some View {
        HStack(spacing: 12) {

            // Severity color strip
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(hex: event.type.severity.colorHex))
                .frame(width: 4)

            // Icon
            Image(systemName: event.type.icon)
                .font(.system(size: 20))
                .foregroundColor(Color(hex: event.type.severity.colorHex))
                .frame(width: 28)

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(event.type.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                Text(event.formattedDateTime)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if let hr = event.heartRate, let br = event.breathingRate {
                    Text(String(format: "HR %.0f bpm  BR %.1f rpm", hr, br))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Acknowledged / acknowledge button
            if event.isAcknowledged {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            } else {
                Button {
                    onAcknowledge()
                } label: {
                    Text("OK")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(Color(hex: event.type.severity.colorHex))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: Color(hex: event.type.severity.colorHex).opacity(0.1),
                radius: 6, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(hex: event.type.severity.colorHex).opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview {
    HistoryView()
}
