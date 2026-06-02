// Views/Main/DashboardView.swift
// Live monitoring home screen with Swift Charts real-time trend visualization.
//
// Displays:
//   • Connection status banner
//   • Emergency call button
//   • Heart rate & breathing rate VitalCards with trend arrows
//   • Guardian / patient role info card
//   • Real-time 30-second dual line charts for HR and BR

import SwiftUI
import Charts

struct DashboardView: View {
    @EnvironmentObject var authViewModel:  AuthViewModel
    @EnvironmentObject var appState:        AppState
    @EnvironmentObject var vitalViewModel: VitalSignViewModel

    // Controls which chart metric is highlighted (nil = both visible)
    @State private var selectedChartSegment: ChartSegment = .both

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {

                    // ── Connection status banner ─────────────────────────────
                    connectionBanner

                    // ── Emergency call button ────────────────────────────────
                    EmergencyCallButton()
                        .padding(.horizontal, 20)

                    // ── Vital sign value cards with trend arrows ─────────────
                    vitalCardsRow
                        .padding(.horizontal, 20)

                    // ── Role-specific info card ──────────────────────────────
                    if authViewModel.isGuardian {
                        guardianStatusCard.padding(.horizontal, 20)
                    } else {
                        monitoredPersonCard.padding(.horizontal, 20)
                    }

                    // ── Real-time chart section ──────────────────────────────
                    liveChartSection
                        .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
                .padding(.top, 12)
            }
            .navigationTitle("Live Monitor")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                // Reconnect to the backend on pull-to-refresh
                vitalViewModel.connectFromSavedSettings()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    // MARK: - Connection Status Banner
    /// Tapping the banner navigates directly to ServerConfigView for quick setup.
    var connectionBanner: some View {
        NavigationLink {
            ServerConfigView()
                .environmentObject(vitalViewModel)
                .environmentObject(appState)
        } label: {
            HStack(spacing: 8) {
                // Status dot
                Circle()
                    .fill(Color(hex: appState.connectionStatus.colorHex))
                    .frame(width: 8, height: 8)

                Text(appState.connectionStatus.displayText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if appState.connectionStatus.isConnected {
                    // Connected: show a small checkmark chip
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(hex: "2E7D32"))
                        .clipShape(Capsule())
                } else {
                    // Disconnected: prompt to configure
                    HStack(spacing: 4) {
                        Text("Tap to Configure")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "9E9E9E"))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Vital Sign Cards
    var vitalCardsRow: some View {
        let data = vitalViewModel.currentData
        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                VitalCard(
                    title:    "Heart Rate",
                    value:    data?.heartRateText ?? "--",
                    unit:     "bpm",
                    icon:     "heart.fill",
                    colorHex: "E53935",
                    status:   data?.heartRateStatus ?? .normal,
                    trend:    vitalViewModel.heartRateTrend
                )
                VitalCard(
                    title:    "Breathing Rate",
                    value:    data?.breathingRateText ?? "--",
                    unit:     "rpm",
                    icon:     "lungs.fill",
                    colorHex: "1976D2",
                    status:   data?.breathingRateStatus ?? .normal,
                    trend:    vitalViewModel.breathingRateTrend
                )
            }
            VitalCard(
                title:    "Body Temperature",
                value:    data?.bodyTemperatureText ?? "--",
                unit:     "°C",
                icon:     "thermometer.medium",
                colorHex: "FF6F00",
                status:   data?.bodyTemperatureStatus ?? .normal
            )

            // ML anomaly score badge — visible only when score ≥ 0.33
            if let score = vitalViewModel.latestAnomalyScore, score >= 0.33 {
                AnomalyScoreBadge(score: score)
            }
        }
    }

    // MARK: - Guardian Status Card
    var guardianStatusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 22))
                .foregroundColor(Color(.systemBlue))

            VStack(alignment: .leading, spacing: 3) {
                Text("Guardian Mode Active")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(.systemBlue))
                Text(appState.notificationsEnabled
                     ? "Strong alerts and push notifications will fire on any anomaly."
                     : "Push notifications are off — please enable them in System Settings.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(appState.notificationsEnabled ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
        }
        .padding(16)
        .background(Color(.systemBlue).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemBlue).opacity(0.2), lineWidth: 1))
    }

    // MARK: - Patient Info Card
    var monitoredPersonCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.arms.open")
                .font(.system(size: 22))
                .foregroundColor(Color(.systemGreen))

            VStack(alignment: .leading, spacing: 3) {
                Text("Patient Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(.systemGreen))
                Text("You can view your live data. Your guardian will be notified on any anomaly.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(.systemGreen).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(.systemGreen).opacity(0.2), lineWidth: 1))
    }

    // MARK: - Live Chart Section (Swift Charts)
    var liveChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Section header + segment picker
            HStack {
                Text("Live Trend (30 s)")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker("Chart", selection: $selectedChartSegment) {
                    ForEach(ChartSegment.allCases) { seg in
                        Text(seg.label).tag(seg)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            if vitalViewModel.realtimeBuffer.isEmpty {
                // Placeholder — shown until MQTT delivers at least one sample
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Waiting for data…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 90)
            } else {
                // Heart Rate chart
                if selectedChartSegment != .breathingRate {
                    chartCard(
                        title:    "Heart Rate (bpm)",
                        color:    Color(hex: "E53935"),
                        data:     vitalViewModel.realtimeBuffer,
                        keyPath:  \.heartRate,
                        yRange:   40...130,
                        refLow:   50,
                        refHigh:  100
                    )
                }

                // Breathing Rate chart
                if selectedChartSegment != .heartRate {
                    chartCard(
                        title:    "Breathing Rate (rpm)",
                        color:    Color(hex: "1976D2"),
                        data:     vitalViewModel.realtimeBuffer,
                        keyPath:  \.breathingRate,
                        yRange:   5...30,
                        refLow:   12,
                        refHigh:  20
                    )
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    /// Generic reusable chart card with normal-range reference band.
    @ViewBuilder
    private func chartCard(
        title:   String,
        color:   Color,
        data:    [VitalSignData],
        keyPath: KeyPath<VitalSignData, Double>,
        yRange:  ClosedRange<Double>,
        refLow:  Double,
        refHigh: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)

            Chart {
                // Normal range shaded background band
                RectangleMark(
                    xStart: nil, xEnd: nil,
                    yStart: .value("Low",  refLow),
                    yEnd:   .value("High", refHigh)
                )
                .foregroundStyle(color.opacity(0.06))

                // Area under the line
                ForEach(data) { point in
                    AreaMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point[keyPath: keyPath])
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.25), color.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }

                // Main line
                ForEach(data) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point[keyPath: keyPath])
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }

                // Highlight the most-recent point
                if let latest = data.last {
                    PointMark(
                        x: .value("Time", latest.timestamp),
                        y: .value("Value", latest[keyPath: keyPath])
                    )
                    .foregroundStyle(color)
                    .symbolSize(30)
                }
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: yRange)
            .chartYAxis {
                AxisMarks(values: .stride(by: (yRange.upperBound - yRange.lowerBound) / 3)) { val in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(height: 90)
        }
    }
}

// MARK: - ML Anomaly Score Badge
struct AnomalyScoreBadge: View {
    let score: Double

    private var colorHex: String { score >= 0.66 ? "B71C1C" : "E65100" }
    private var label: String     { score >= 0.66 ? "High Risk" : "Elevated" }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 13))
            Text("AI Anomaly · \(Int(score * 100))%")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(hex: colorHex).opacity(0.15))
                .clipShape(Capsule())
        }
        .foregroundColor(Color(hex: colorHex))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(hex: colorHex).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: colorHex).opacity(0.25), lineWidth: 1))
    }
}

// MARK: - Chart Segment Enum
enum ChartSegment: String, CaseIterable, Identifiable {
    case both         = "both"
    case heartRate    = "hr"
    case breathingRate = "br"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .both:          return "Both"
        case .heartRate:     return "HR"
        case .breathingRate: return "BR"
        }
    }
}

// MARK: - VitalCard Component
/// Numeric vital-sign card with status badge and trend direction arrow.
struct VitalCard: View {
    let title:    String
    let value:    String
    let unit:     String
    let icon:     String
    let colorHex: String
    let status:   VitalStatus
    var trend:    TrendDirection = .stable

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Icon + title row
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Color(hex: colorHex))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                // Trend direction arrow
                Image(systemName: trend.sfSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(trendArrowColor)
            }

            // Large numeric value
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundColor(statusValueColor)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: value)
                Text(unit)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(.bottom, 4)
            }

            // Status badge
            HStack(spacing: 4) {
                Image(systemName: status.sfSymbol)
                    .font(.system(size: 10))
                Text(status.displayText)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Color(hex: status.colorHex))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: status.colorHex).opacity(0.12))
            .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(hex: colorHex).opacity(0.12), radius: 8, y: 3)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(statusBorderColor, lineWidth: 1.5)
        )
    }

    // Color the value digit based on status (red for critical, orange for warning)
    private var statusValueColor: Color {
        switch status {
        case .critical: return Color(hex: "D32F2F")
        case .warning:  return Color(hex: "E65100")
        case .normal:   return Color(hex: colorHex)
        }
    }

    private var statusBorderColor: Color {
        switch status {
        case .critical: return Color(hex: "D32F2F").opacity(0.4)
        case .warning:  return Color(hex: "E65100").opacity(0.3)
        case .normal:   return Color(hex: colorHex).opacity(0.15)
        }
    }

    /// Trend arrow color: neutral (grey) for stable, contextual otherwise
    private var trendArrowColor: Color {
        switch trend {
        case .stable: return .secondary.opacity(0.5)
        case .up:     return Color(hex: "E53935").opacity(0.8)
        case .down:   return Color(hex: "1976D2").opacity(0.8)
        }
    }
}

// MARK: - Preview
#Preview {
    let auth  = AuthViewModel()
    let state = AppState()
    let vital = VitalSignViewModel()
    return DashboardView()
        .environmentObject(auth)
        .environmentObject(state)
        .environmentObject(vital)
}
