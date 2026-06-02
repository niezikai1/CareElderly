// ViewModels/VitalSignViewModel.swift
// Manages the real-time vital-sign data pipeline.
//
// Data is shown ONLY when MQTT is connected. No simulation fallback.
//
// Responsibilities:
//   1. Own a MQTTService and observe its connection / data events.
//   2. Maintain a 30-sample rolling buffer for Swift Charts (≈ 30 s at 1 Hz).
//   3. Persist incoming samples to Core Data (throttled: every N samples).
//   4. Expose pendingAlertEvent for the App layer to forward to AppState.

import Foundation
import Combine

// MARK: - Trend direction helper
/// Indicates whether a metric is trending upward, downward, or staying stable.
enum TrendDirection {
    case up
    case down
    case stable

    var sfSymbol: String {
        switch self {
        case .up:     return "arrow.up.right"
        case .down:   return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    /// Color hint for the trend arrow (contextual — callers can override)
    var colorHex: String {
        switch self {
        case .up:     return "E53935"  // red
        case .down:   return "1976D2"  // blue
        case .stable: return "00C853"  // green
        }
    }
}

// MARK: - VitalSignViewModel
class VitalSignViewModel: ObservableObject {

    // MARK: Published — consumed by DashboardView
    /// Most recently received vital sign packet; nil when disconnected.
    @Published var currentData: VitalSignData? = nil

    /// Rolling 30-sample window for the real-time chart (1 Hz → ≈ 30 seconds)
    @Published var realtimeBuffer: [VitalSignData] = []

    /// Set to non-nil when an alert arrives from the backend.
    /// The App level reads this and forwards it to AppState, then resets to nil.
    @Published var pendingAlertEvent: AlertEvent? = nil

    /// Latest ML reconstruction-error anomaly score [0, 1].
    /// Smoothed continuous anomaly score derived from recent sliding windows.
    /// Nil until the buffer accumulates 30 real samples.
    @Published var latestAnomalyScore: Double? = nil

    /// Last valid ML anomaly score retained across disconnects for display purposes.
    @Published var lastKnownAnomalyScore: Double? = nil

    /// Short rolling history of ML anomaly scores for continuous processing and UI trends.
    @Published var anomalyScoreHistory: [AnomalyScorePoint] = []

    // MARK: Owned services
    let mqttService: MQTTService

    // MARK: Private
    private let persistence          = PersistenceController.shared
    private let analytics            = HealthAnalyticsService.shared
    private var cancellables         = Set<AnyCancellable>()

    /// Persist to Core Data once every this many incoming packets (avoid excess I/O)
    private let persistInterval      = 5
    private var samplesSinceLastSave = 0

    /// ML-based consecutive anomaly window tracking.
    /// Increments each time the model scores the current window as high-risk;
    /// resets to 0 on any lower-scoring window or on MQTT disconnect.
    private var consecutiveAnomalyWindows = 0
    private let anomalyWindowThreshold    = 10   // fire alert after this many consecutive windows
    private let anomalyScoreHistoryLimit  = 120
    private let anomalySmoothingWindow    = 5

    /// Rule-based alert cooldown — prevents firing more than once per 30 s.
    private var lastRuleAlertAt: Date = .distantPast
    private let ruleAlertCooldown: TimeInterval = 30

    // MARK: - Init
    init(mqttService: MQTTService = MQTTService()) {
        self.mqttService = mqttService
        bindMQTT()
    }

    // MARK: - MQTT Binding

    private func bindMQTT() {

        // React to connection status changes.
        mqttService.$connectionStatus
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                if case .connected = status {
                    self.realtimeBuffer.removeAll()
                    self.consecutiveAnomalyWindows = 0
                    self.anomalyScoreHistory.removeAll()
                    self.latestAnomalyScore = nil
                } else if case .disconnected = status {
                    self.currentData = nil
                    self.realtimeBuffer.removeAll()
                    self.consecutiveAnomalyWindows = 0
                    self.anomalyScoreHistory.removeAll()
                    self.latestAnomalyScore = nil
                }
            }
            .store(in: &cancellables)

        // Forward incoming vital-sign packets into the pipeline
        mqttService.$lastVitalSign
            .compactMap { $0 }              // Skip nil (initial value)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vital in self?.ingest(vital) }
            .store(in: &cancellables)

        // Forward incoming alert events to the App layer
        mqttService.$pendingAlertEvent
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.pendingAlertEvent = event
            }
            .store(in: &cancellables)
    }

    // MARK: - Data Ingestion

    /// Process one incoming vital-sign sample: update display, buffer, Core Data, and ML check.
    private func ingest(_ data: VitalSignData) {
        currentData = data

        // Append to rolling buffer; cap at 30 samples
        realtimeBuffer.append(data)
        if realtimeBuffer.count > 30 { realtimeBuffer.removeFirst() }

        // Throttled Core Data persistence
        samplesSinceLastSave += 1
        if samplesSinceLastSave >= persistInterval {
            samplesSinceLastSave = 0
            VitalSignRecord.insert(from: data, in: persistence.context)
            persistence.save()
        }

        // Rule-based threshold check — fires immediately, 30 s cooldown.
        checkRuleBasedAlert(data)

        // ML anomaly check — run CoreML inference on a background thread so the
        // main thread stays free for UI events (keyboard input, animations, etc.).
        guard realtimeBuffer.count >= 30 else { return }
        let bufferSnap = realtimeBuffer
        let dataSnap   = data
        Task.detached(priority: .userInitiated) { [weak self, analytics] in
            guard let self else { return }
            let result = analytics.anomalyResult(current: dataSnap,
                                                 buffer: bufferSnap,
                                                 baseline: nil)
            await MainActor.run {
                self.anomalyScoreHistory.append(AnomalyScorePoint(timestamp: dataSnap.timestamp,
                                                                 score: result.score))
                if self.anomalyScoreHistory.count > self.anomalyScoreHistoryLimit {
                    self.anomalyScoreHistory.removeFirst(self.anomalyScoreHistory.count - self.anomalyScoreHistoryLimit)
                }

                let recentScores = self.anomalyScoreHistory.map(\.score)
                let continuousScore = analytics.smoothedAnomalyScore(from: recentScores,
                                                                     windowSize: self.anomalySmoothingWindow) ?? result.score
                self.latestAnomalyScore = continuousScore
                self.lastKnownAnomalyScore = continuousScore

                if continuousScore >= 0.70 {
                    self.consecutiveAnomalyWindows += 1
                    if self.consecutiveAnomalyWindows == self.anomalyWindowThreshold {
                        self.consecutiveAnomalyWindows = 0
                        guard Date().timeIntervalSince(self.lastRuleAlertAt) >= self.ruleAlertCooldown else { return }
                        self.lastRuleAlertAt = Date()
                        self.pendingAlertEvent = AlertEvent(type: .mlAnomaly,
                                                            heartRate: dataSnap.heartRate,
                                                            breathingRate: dataSnap.breathingRate)
                    }
                } else {
                    self.consecutiveAnomalyWindows = 0
                }
            }
        }
    }

    // MARK: - Rule-based Alert

    private func checkRuleBasedAlert(_ data: VitalSignData) {
        guard data.isCritical else { return }
        guard Date().timeIntervalSince(lastRuleAlertAt) >= ruleAlertCooldown else { return }
        lastRuleAlertAt = Date()

        let alertType: AlertType
        if data.heartRateStatus == .critical {
            alertType = data.heartRate < 50 ? .heartRateLow : .heartRateHigh
        } else if data.breathingRateStatus == .critical {
            alertType = .breathRateAbnormal
        } else {
            alertType = .heartRateLow   // bodyTemp critical fallback
        }
        pendingAlertEvent = AlertEvent(type: alertType,
                                       heartRate: data.heartRate,
                                       breathingRate: data.breathingRate)
    }

    // MARK: - Public API

    /// Called by the App after login. Attempts to connect to the saved broker if configured.
    func connectFromSavedSettings() {
        let host     = UserDefaults.standard.string(forKey: "mqttHost")  ?? ""
        let portInt  = UserDefaults.standard.integer(forKey: "mqttPort")
        let port     = UInt16(portInt > 0 ? portInt : 1883)
        let topic    = UserDefaults.standard.string(forKey: "mqttTopic") ?? "vitals"
        guard !host.isEmpty else { return }
        mqttService.connect(host: host, port: port, topic: topic)
    }

    /// Called on logout. Clears all live data and disconnects.
    func reset() {
        currentData = nil
        realtimeBuffer = []
        latestAnomalyScore = nil
        lastKnownAnomalyScore = nil
        anomalyScoreHistory = []
        consecutiveAnomalyWindows = 0
        mqttService.disconnect()
    }

    /// Connect to an MQTT broker with explicit parameters.
    func connect(host: String, port: UInt16 = 1883, topic: String,
                 username: String = "", password: String = "", useTLS: Bool = false) {
        mqttService.connect(host: host, port: port, topic: topic,
                            username: username, password: password, useTLS: useTLS)
    }

    /// Cleanly disconnect from the broker.
    func disconnect() {
        mqttService.disconnect()
    }

    // MARK: - Trend Computation
    // Compare mean of newest 5 samples vs. previous 5 samples to detect direction.

    /// Trend direction for heart rate
    var heartRateTrend: TrendDirection {
        computeTrend(keyPath: \.heartRate, threshold: 3.0)
    }

    /// Trend direction for breathing rate
    var breathingRateTrend: TrendDirection {
        computeTrend(keyPath: \.breathingRate, threshold: 1.5)
    }

    private func computeTrend(keyPath: KeyPath<VitalSignData, Double>,
                               threshold: Double) -> TrendDirection {
        guard realtimeBuffer.count >= 10 else { return .stable }
        let n      = realtimeBuffer.count
        let newer  = realtimeBuffer[(n - 5)...].map { $0[keyPath: keyPath] }
        let older  = realtimeBuffer[(n - 10)..<(n - 5)].map { $0[keyPath: keyPath] }
        let delta  = newer.reduce(0, +) / 5.0 - older.reduce(0, +) / 5.0
        if      delta >  threshold { return .up }
        else if delta < -threshold { return .down }
        else                        { return .stable }
    }
}
