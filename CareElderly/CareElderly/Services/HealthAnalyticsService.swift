// Services/HealthAnalyticsService.swift
// Health data analytics: HRV estimation, personalised baseline construction,
// and LSTM Autoencoder anomaly scoring (VitalAnomalyDetector.mlpackage).
//
// Primary anomaly path: CoreML LSTM Autoencoder trained on BIDMC dataset.
// Fallback: z-score against personal baseline when model is unavailable.
//
// Reference methodology:
//   Task Force of ESC/NASPE (1996). "Heart Rate Variability — Standards of
//   Measurement, Physiological Interpretation, and Clinical Use."
//   Circulation, 93(5), 1043–1065.

import Foundation
import CoreML

// MARK: - HRV Metrics

/// Short-term HRV derived from the 30-second rolling vital-sign buffer.
/// Because the sensor delivers one HR sample per second (not individual
/// R-R intervals), we first convert each sample to an approximate interval:
///   RR_i  =  60 000 / HR_i   (milliseconds)
/// then apply standard time-domain formulae to the resulting RR series.
struct HRVMetrics {
    /// Root Mean Square of Successive Differences (ms).
    /// Primary index of parasympathetic (vagal) activity; higher is healthier.
    let rmssd: Double?

    /// Standard Deviation of RR intervals (ms).
    /// Reflects overall autonomic modulation.
    let sdnn: Double?

    /// Mean RR interval (ms) — reciprocal of mean heart rate.
    let meanRR: Double?

    let sampleCount: Int

    /// Qualitative label derived from published adult RMSSD reference ranges.
    var interpretation: HRVLevel {
        guard let r = rmssd else { return .insufficient }
        if r >= 40 { return .good }
        if r >= 20 { return .fair }
        return .low
    }

    enum HRVLevel: String {
        case good         = "Good"
        case fair         = "Fair"
        case low          = "Low"
        case insufficient = "Insufficient Data"

        var colorHex: String {
            switch self {
            case .good:         return "2E7D32"
            case .fair:         return "F57C00"
            case .low:          return "D32F2F"
            case .insufficient: return "9E9E9E"
            }
        }

        var icon: String {
            switch self {
            case .good:         return "checkmark.circle.fill"
            case .fair:         return "minus.circle.fill"
            case .low:          return "exclamationmark.circle.fill"
            case .insufficient: return "questionmark.circle.fill"
            }
        }

        var description: String {
            switch self {
            case .good:         return "Healthy autonomic balance"
            case .fair:         return "Moderate variability"
            case .low:          return "Reduced variability"
            case .insufficient: return "Need more data"
            }
        }
    }
}

// MARK: - Personal Baseline

/// Statistical profile built from the user's own historical Core Data records.
/// Enables anomaly scoring relative to *this individual's* normal range
/// rather than a population-level threshold — a key advantage over fixed limits.
struct HealthBaseline {
    let meanHR:      Double   // bpm
    let stdHR:       Double   // bpm
    let meanBR:      Double   // rpm
    let stdBR:       Double   // rpm
    let sampleCount: Int

    /// At least 30 samples are needed for a statistically meaningful baseline.
    nonisolated var isReliable: Bool { sampleCount >= 30 }

    /// Combined z-score anomaly metric normalised to [0, 1].
    ///
    /// z(HR) = |HR − μ_HR| / σ_HR
    /// z(BR) = |BR − μ_BR| / σ_BR
    /// score = min( (z_HR + z_BR) / 6,  1.0 )
    ///
    /// A 3σ deviation on *either* axis alone yields score ≈ 0.5;
    /// simultaneous 3σ deviations on both axes yield score = 1.0.
    nonisolated func anomalyScore(hr: Double, br: Double) -> Double {
        guard stdHR > 0.1, stdBR > 0.1 else { return 0 }
        let zHR = abs(hr - meanHR) / stdHR
        let zBR = abs(br - meanBR) / stdBR
        return min((zHR + zBR) / 6.0, 1.0)
    }
}

// MARK: - Anomaly Result

struct AnomalyResult {
    let score:          Double   // 0.0 – 1.0
    let level:          Level
    let baselineSamples: Int

    enum Level {
        case normal, elevated, high

        var label: String {
            switch self {
            case .normal:   return "Normal"
            case .elevated: return "Elevated"
            case .high:     return "High Risk"
            }
        }

        var colorHex: String {
            switch self {
            case .normal:   return "2E7D32"
            case .elevated: return "F57C00"
            case .high:     return "D32F2F"
            }
        }

        var icon: String {
            switch self {
            case .normal:   return "checkmark.shield.fill"
            case .elevated: return "exclamationmark.shield.fill"
            case .high:     return "xmark.shield.fill"
            }
        }

        var description: String {
            switch self {
            case .normal:   return "Vital-sign pattern looks normal"
            case .elevated: return "Mild anomaly detected by AI model"
            case .high:     return "Significant anomaly — monitor closely"
            }
        }
    }
}

struct AnomalyScorePoint: Identifiable {
    let id = UUID()
    let timestamp: Date
    let score: Double
}

// MARK: - HealthAnalyticsService

// @unchecked Sendable: anomalyModel is a `let` set once in init and then
// read-only — safe to share across actor boundaries without a lock.
final class HealthAnalyticsService: @unchecked Sendable {

    static let shared = HealthAnalyticsService()

    // MARK: CoreML — LSTM Autoencoder anomaly detector
    // Stored as `let` so concurrent reads from background threads are safe.
    // Bundle(for:) is used instead of Bundle.main to avoid the @MainActor
    // annotation on Bundle.main that would otherwise cascade to every method.
    private nonisolated(unsafe) let anomalyModel: MLModel?

    private init() {
        let bundle = Bundle(for: HealthAnalyticsService.self)
        if let url = bundle.url(forResource: "VitalAnomalyDetector",
                                 withExtension: "mlmodelc") {
            anomalyModel = try? MLModel(contentsOf: url)
        } else {
            print("ℹ️ VitalAnomalyDetector.mlmodelc not found — using z-score fallback")
            anomalyModel = nil
        }
    }

    // MARK: HRV from rolling buffer

    /// Compute HRV metrics from a sequence of VitalSignData samples.
    /// Works best with the 30-sample 1-Hz buffer from VitalSignViewModel.
    nonisolated func computeHRV(from samples: [VitalSignData]) -> HRVMetrics {
        let hrs = samples.map { $0.heartRate }
        guard hrs.count >= 5 else {
            return HRVMetrics(rmssd: nil, sdnn: nil, meanRR: nil, sampleCount: hrs.count)
        }

        // Convert bpm → approximate RR intervals (ms)
        let rr = hrs.map { 60_000.0 / $0 }
        let n  = Double(rr.count)

        // Mean RR
        let meanRR = rr.reduce(0, +) / n

        // SDNN: population std dev of RR
        let sdnn = sqrt(rr.map { pow($0 - meanRR, 2) }.reduce(0, +) / n)

        // RMSSD: root mean square of successive differences
        let diffs  = zip(rr.dropFirst(), rr).map { $0 - $1 }
        let rmssd  = sqrt(diffs.map { $0 * $0 }.reduce(0, +) / Double(diffs.count))

        return HRVMetrics(
            rmssd:       rmssd,
            sdnn:        sdnn,
            meanRR:      meanRR,
            sampleCount: rr.count
        )
    }

    // MARK: Baseline from historical records

    /// Build a personal baseline from Core Data VitalSignRecord objects.
    /// Returns nil when fewer than 10 records are available.
    nonisolated func computeBaseline(from records: [VitalSignRecord]) -> HealthBaseline? {
        guard records.count >= 10 else { return nil }
        let hrs = records.map { $0.heartRate }
        let brs = records.map { $0.breathingRate }
        return HealthBaseline(
            meanHR:      mean(hrs),
            stdHR:       std(hrs),
            meanBR:      mean(brs),
            stdBR:       std(brs),
            sampleCount: records.count
        )
    }

    // MARK: Anomaly scoring

    /// Produce a risk assessment using the LSTM Autoencoder when the 30-sample buffer
    /// is available, otherwise falling back to the personalised z-score baseline.
    nonisolated func anomalyResult(current: VitalSignData,
                                   buffer: [VitalSignData] = [],
                                   baseline: HealthBaseline?) -> AnomalyResult {
        // Primary: CoreML LSTM Autoencoder reconstruction error
        if buffer.count >= 30,
           let score = mlReconstructionScore(from: Array(buffer.suffix(30))) {
            return AnomalyResult(score: score,
                                 level: anomalyLevel(for: score),
                                 baselineSamples: buffer.count)
        }

        // Fallback: personalised z-score baseline
        guard let b = baseline, b.isReliable else {
            return AnomalyResult(score: 0, level: .normal, baselineSamples: baseline?.sampleCount ?? 0)
        }
        let score = b.anomalyScore(hr: current.heartRate, br: current.breathingRate)
        return AnomalyResult(score: score,
                             level: anomalyLevel(for: score),
                             baselineSamples: b.sampleCount)
    }

    nonisolated func anomalyLevel(for score: Double) -> AnomalyResult.Level {
        if score < 0.33 { return .normal }
        if score < 0.66 { return .elevated }
        return .high
    }

    nonisolated func smoothedAnomalyScore(from recentScores: [Double], windowSize: Int = 5) -> Double? {
        let tail = Array(recentScores.suffix(windowSize))
        guard !tail.isEmpty else { return nil }

        let weightSum = Double((1...tail.count).reduce(0, +))
        let weightedTotal = zip(tail, 1...tail.count).reduce(0.0) { partial, pair in
            partial + pair.0 * Double(pair.1)
        }
        return weightedTotal / weightSum
    }

    // MARK: Private: CoreML inference

    /// Run the LSTM Autoencoder on a 30-sample window and return a normalised [0, 1]
    /// anomaly score derived from the reconstruction MSE.
    ///
    /// Input normalisation (min-max, from training data):
    ///   HR:  [50, 100] bpm  → [0, 1]
    ///   BR:  [12,  20] rpm  → [0, 1]
    /// Values are clamped to [0, 1] so out-of-range readings don't corrupt the tensor.
    ///
    /// Score mapping:  score = min(MSE / 0.00950, 1.0)  — threshold_test.json 95th-percentile (test set)
    private nonisolated func mlReconstructionScore(from samples: [VitalSignData]) -> Double? {
        guard samples.count == 30, let model = anomalyModel else {
            print("⚠️ ML: model=\(anomalyModel == nil ? "nil" : "ok"), samples=\(samples.count)")
            return nil
        }

        guard let input = try? MLMultiArray(shape: [1, 30, 2], dataType: .float32) else { return nil }
        for (i, s) in samples.enumerated() {
            let hrNorm = Float(min(max((s.heartRate    - 50) / 50, 0), 1))
            let brNorm = Float(min(max((s.breathingRate - 12) /  8, 0), 1))
            input[[0, NSNumber(value: i), 0]] = NSNumber(value: hrNorm)
            input[[0, NSNumber(value: i), 1]] = NSNumber(value: brNorm)
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["vitals": input]),
              let output   = try? model.prediction(from: provider)
        else {
            print("⚠️ ML: prediction failed")
            return nil
        }

        print("🧠 ML output features: \(output.featureNames)")

        guard let recon = output.featureValue(for: "reconstruction")?.multiArrayValue else {
            print("⚠️ ML: 'reconstruction' not found — check output name above")
            return nil
        }

        print("🧠 ML recon shape: \(recon.shape)  input[0,0]: hr=\(input[[0,0,0]]) br=\(input[[0,0,1]])  recon[0,0]: \(recon[0]) \(recon[1])")

        var mse = 0.0
        for i in 0..<30 {
            for j in 0..<2 {
                let idx: [NSNumber] = [0, NSNumber(value: i), NSNumber(value: j)]
                let diff = input[idx].doubleValue - recon[idx].doubleValue
                mse += diff * diff
            }
        }
        mse /= 60.0
        // 0.004205 = 95th-percentile test-set reconstruction error (threshold_test.json)
        print("🧠 ML MSE=\(String(format: "%.5f", mse))  score=\(String(format: "%.3f", min(mse/0.004205, 1.0)))")

        return min(mse / 0.004205, 1.0)
    }

    // MARK: Private helpers

    private nonisolated func mean(_ v: [Double]) -> Double {
        v.reduce(0, +) / Double(v.count)
    }

    private nonisolated func std(_ v: [Double]) -> Double {
        let m = mean(v)
        return sqrt(v.map { pow($0 - m, 2) }.reduce(0, +) / Double(v.count))
    }
}
