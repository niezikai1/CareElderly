// Views/Analytics/AnalyticsView.swift
// "Health Insights" tab — AI-powered health analytics dashboard.
//
// Features:
//   • Personalised anomaly score gauge (z-score vs. individual baseline)
//   • Live HRV card (RMSSD, SDNN from 30-second rolling buffer)
//   • Baseline statistics card (learned from historical Core Data records)
//   • Data quality indicator showing sample count

import SwiftUI
import Charts

struct AnalyticsView: View {

    @EnvironmentObject var vitalViewModel: VitalSignViewModel
    @StateObject private var historyVM = HistoryViewModel()

    private let analytics = HealthAnalyticsService.shared

    // Cached ML/HRV results — updated on background to avoid blocking the main thread.
    @State private var liveHRV = HRVMetrics(rmssd: nil, sdnn: nil, meanRR: nil, sampleCount: 0)
    @State private var anomalyResult = AnomalyResult(score: 0, level: .normal, baselineSamples: 0)

    private var isMLReady: Bool {
        vitalViewModel.realtimeBuffer.count >= 30
    }

    private var displayedAnomalyScore: Double? {
        if isMLReady {
            return anomalyResult.score
        }
        return vitalViewModel.lastKnownAnomalyScore
    }

    private var displayedAnomalyLevel: AnomalyResult.Level? {
        guard let score = displayedAnomalyScore else { return nil }
        return analytics.anomalyLevel(for: score)
    }

    private var isShowingLastKnownScore: Bool {
        !isMLReady && vitalViewModel.lastKnownAnomalyScore != nil
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {

                    // ── Anomaly score gauge ──────────────────────────────────
                    anomalyGaugeCard
                        .padding(.horizontal, 16)

                    // ── Live HRV card ────────────────────────────────────────
                    liveHRVCard
                        .padding(.horizontal, 16)

                    // ── Baseline statistics card ─────────────────────────────
                    baselineCard
                        .padding(.horizontal, 16)

                    // ── Method note ─────────────────────────────────────────
                    methodNote
                        .padding(.horizontal, 16)

                    // ── Disclaimer ───────────────────────────────────────────
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                        Text("ML data is for reference only. Consult a doctor if you feel unwell.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 16)

                    Spacer(minLength: 24)
                }
                .padding(.top, 12)
            }
            .navigationTitle("Health Insights")
            .navigationBarTitleDisplayMode(.large)
            // Only recompute when real data arrives (onChange skips the initial appear,
            // preventing a stale/mock result from flashing on every tab switch).
            .onChange(of: vitalViewModel.currentData?.timestamp) { _, _ in
                guard let current = vitalViewModel.currentData else { return }
                let buffer   = vitalViewModel.realtimeBuffer
                let baseline = historyVM.baseline
                let continuousScore = vitalViewModel.latestAnomalyScore
                Task {
                    let (hrv, result) = await Task.detached(priority: .userInitiated) { [analytics] in
                        let h = analytics.computeHRV(from: buffer)
                        let r: AnomalyResult
                        if buffer.count >= 30, let continuousScore {
                            r = AnomalyResult(score: continuousScore,
                                              level: analytics.anomalyLevel(for: continuousScore),
                                              baselineSamples: buffer.count)
                        } else {
                            r = analytics.anomalyResult(current: current, buffer: buffer, baseline: baseline)
                        }
                        return (h, r)
                    }.value
                    liveHRV = hrv
                    anomalyResult = result
                }
            }
        }
    }

    // MARK: - Anomaly Gauge Card

    var anomalyGaugeCard: some View {
        VStack(spacing: 16) {
            HStack {
                Label("Anomaly Score", systemImage: "brain.head.profile")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Image(systemName: displayedAnomalyLevel?.icon ?? "minus.circle")
                    .foregroundColor(displayedAnomalyLevel.map { Color(hex: $0.colorHex) } ?? .secondary)
            }

            AnomalyGaugeShape(value: displayedAnomalyScore,
                              colorHex: displayedAnomalyLevel?.colorHex ?? "9E9E9E")
                .frame(height: 160)

            VStack(spacing: 4) {
                Text(displayedAnomalyLevel?.label ?? "--")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(displayedAnomalyLevel.map { Color(hex: $0.colorHex) } ?? .secondary)
                Text(anomalyStatusDescription)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Show status hint only when the ML buffer isn't full yet
            if vitalViewModel.realtimeBuffer.count < 30 {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 12))
                    Text("Warming up — need \(30 - vitalViewModel.realtimeBuffer.count) more samples for ML scoring")
                        .font(.system(size: 12))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6))
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private var baselineStatusText: String {
        guard let b = historyVM.baseline else {
            return "Collecting baseline data…"
        }
        let needed = 30 - b.sampleCount
        return "Need \(needed) more samples for reliable baseline"
    }

    private var anomalyStatusDescription: String {
        if isMLReady {
            return anomalyResult.level.description
        }
        if isShowingLastKnownScore {
            return "Disconnected — showing last known ML score"
        }
        return "Waiting for 30 samples before ML scoring"
    }

    // MARK: - Live HRV Card

    var liveHRVCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Live HRV  (30 s buffer)", systemImage: "waveform.path.ecg.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: liveHRV.interpretation.icon)
                    Text(liveHRV.interpretation.rawValue)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(Color(hex: liveHRV.interpretation.colorHex))
            }

            HStack(spacing: 0) {
                hrvCell(
                    label: "RMSSD",
                    value: liveHRV.rmssd.map { String(format: "%.1f", $0) } ?? "—",
                    unit:  "ms",
                    description: "Vagal tone"
                )
                Divider().frame(height: 60)
                hrvCell(
                    label: "SDNN",
                    value: liveHRV.sdnn.map { String(format: "%.1f", $0) } ?? "—",
                    unit:  "ms",
                    description: "Overall HRV"
                )
                Divider().frame(height: 60)
                hrvCell(
                    label: "Mean RR",
                    value: liveHRV.meanRR.map { String(format: "%.0f", $0) } ?? "—",
                    unit:  "ms",
                    description: "Avg interval"
                )
            }

            Text(liveHRV.interpretation.description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func hrvCell(label: String, value: String,
                         unit: String, description: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Baseline Card

    var baselineCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Personal Baseline", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                if let b = historyVM.baseline {
                    Text("\(b.sampleCount) samples")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }

            if let b = historyVM.baseline {
                HStack(spacing: 0) {
                    baselineCell(
                        icon:     "heart.fill",
                        colorHex: "E53935",
                        label:    "Heart Rate",
                        mean:     b.meanHR,
                        std:      b.stdHR,
                        unit:     "bpm",
                        current:  vitalViewModel.currentData?.heartRate
                    )
                    Divider().frame(height: 72)
                    baselineCell(
                        icon:     "lungs.fill",
                        colorHex: "1976D2",
                        label:    "Breathing",
                        mean:     b.meanBR,
                        std:      b.stdBR,
                        unit:     "rpm",
                        current:  vitalViewModel.currentData?.breathingRate
                    )
                }

                if !b.isReliable {
                    ProgressView(value: Double(b.sampleCount), total: 30) {
                        Text("Baseline quality: \(b.sampleCount)/30 samples")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .tint(Color(hex: "1976D2"))
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Collecting baseline data…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func baselineCell(icon: String, colorHex: String,
                              label: String, mean: Double, std: Double,
                              unit: String, current: Double?) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: colorHex))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
            Text(String(format: "%.0f ± %.0f", mean, std))
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(Color(hex: colorHex))
            Text("\(unit) · your norm")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            HStack(spacing: 3) {
                Text("Now:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(current.map { String(format: "%.0f", $0) } ?? "--")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: colorHex))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Method Note

    var methodNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1976D2"))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("Methodology")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(.systemBlue))
                Text("Anomaly scoring uses a PyTorch LSTM Autoencoder (trained on BIDMC, input [30 × 2]) converted via coremltools; reconstruction error above threshold indicates anomaly. Falls back to personalised z-score baseline when the 30-sample buffer is unavailable. HRV is computed from 1-Hz HR samples per ESC/NASPE (1996) guidelines.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(Color(.systemBlue).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Anomaly Gauge Shape

/// Speedometer-style 240° arc gauge.
/// The arc sweeps from the bottom-left (≈ 7 o'clock) clockwise through
/// the top to the bottom-right (≈ 5 o'clock), mirroring a car rev counter.
private struct AnomalyGaugeShape: View {
    let value:    Double?   // 0.0 – 1.0
    let colorHex: String

    // Trim parameters: the arc occupies 240/360 of the full circle.
    private let trackFraction: Double = 240.0 / 360.0
    // The arc starts at the 7-o'clock position (150° clockwise from 3 o'clock).
    private let startDegrees:  Double = 150.0

    var body: some View {
        ZStack {
            // Background track (full 240°)
            Circle()
                .trim(from: 0, to: trackFraction)
                .stroke(Color(.systemGray5),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round))
                .rotationEffect(.degrees(startDegrees))

            // Value arc
            Circle()
                .trim(from: 0, to: (value ?? 0) * trackFraction)
                .stroke(
                    LinearGradient(
                        colors: [Color(hex: "2E7D32"), Color(hex: "F57C00"), Color(hex: colorHex)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 20, lineCap: .round)
                )
                .rotationEffect(.degrees(startDegrees))
                .animation(.easeInOut(duration: 0.7), value: value ?? 0)

            // Tick marks at 0 %, 50 %, 100 %
            ForEach([0.0, 0.5, 1.0], id: \.self) { t in
                TickMark(fraction: t * trackFraction, startDegrees: startDegrees)
                    .stroke(Color(.systemGray3), lineWidth: 2)
            }

            // Centre numeric display
            VStack(spacing: 2) {
                Text(value.map { String(format: "%.0f", $0 * 100) } ?? "--")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(Color(hex: colorHex))
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.4), value: value ?? 0)
                Text("anomaly score")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .offset(y: 10)
        }
        .padding(24)
    }
}

// A small radial tick at a given fraction of the full circle.
private struct TickMark: Shape {
    let fraction:     Double
    let startDegrees: Double

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let angle  = Angle(degrees: startDegrees + fraction * 360)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner  = radius * 0.82
        let outer  = radius * 0.92
        let cos    = CGFloat(Foundation.cos(angle.radians))
        let sin    = CGFloat(Foundation.sin(angle.radians))
        p.move(to:   CGPoint(x: center.x + cos * inner, y: center.y + sin * inner))
        p.addLine(to: CGPoint(x: center.x + cos * outer, y: center.y + sin * outer))
        return p
    }
}

// MARK: - Preview
#Preview {
    AnalyticsView()
        .environmentObject(VitalSignViewModel())
}
