// Models/AlertEvent.swift
// Alert event model: defines alert types, severity levels, and action advice

import Foundation

// MARK: - Alert Type
enum AlertType: String, Codable, CaseIterable {
    case heartStop          = "heart_stop"
    case breathStop         = "breath_stop"
    case fall               = "fall"
    case heartRateHigh      = "heart_rate_high"
    case heartRateLow       = "heart_rate_low"
    case breathRateAbnormal = "breath_rate_abnormal"
    case mlAnomaly          = "ml_anomaly"

    var displayName: String {
        switch self {
        case .heartStop:           return "Cardiac Arrest"
        case .breathStop:          return "Respiratory Arrest"
        case .fall:                return "Fall Detected"
        case .heartRateHigh:       return "High Heart Rate"
        case .heartRateLow:        return "Low Heart Rate"
        case .breathRateAbnormal:  return "Abnormal Breathing"
        case .mlAnomaly:           return "ML Anomaly Detected"
        }
    }

    var icon: String {
        switch self {
        case .heartStop, .heartRateHigh, .heartRateLow: return "heart.fill"
        case .breathStop, .breathRateAbnormal:           return "lungs.fill"
        case .fall:                                       return "figure.fall"
        case .mlAnomaly:                                  return "brain.head.profile"
        }
    }

    /// Action advice displayed to guardian
    var advice: String {
        switch self {
        case .heartStop:
            return "Possible cardiac arrest! Check the patient immediately. Call 911 and begin CPR if necessary."
        case .breathStop:
            return "Possible respiratory arrest! Check that the airway is clear. Call emergency services immediately."
        case .fall:
            return "A fall has been detected. Go check on the patient immediately. Call 911 if they are injured."
        case .heartRateHigh:
            return "Heart rate is elevated. Have the patient rest and avoid stress. Seek medical care if it persists."
        case .heartRateLow:
            return "Heart rate is low. Check on the patient soon. Seek medical care if they feel dizzy or weak."
        case .breathRateAbnormal:
            return "Abnormal breathing rate detected. Monitor the patient closely and consult a doctor if it continues."
        case .mlAnomaly:
            return "The AI model has detected a sustained abnormal vital-sign pattern. Please check on the patient."
        }
    }

    /// Whether this is a critical (life-threatening) alert
    var isCritical: Bool {
        return self == .heartStop || self == .breathStop || self == .fall
    }

    var severity: AlertSeverity {
        return isCritical ? .critical : .warning
    }
}

// MARK: - Alert Severity
enum AlertSeverity: String, Codable {
    case warning  // Yellow warning
    case critical // Red critical

    var colorHex: String {
        switch self {
        case .warning:  return "E65100"
        case .critical: return "B71C1C"
        }
    }

    var displayText: String {
        switch self {
        case .warning:  return "Warning"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Alert Event Record
struct AlertEvent: Identifiable, Codable {
    let id: UUID
    let type: AlertType
    let timestamp: Date
    let heartRate: Double?      // Heart rate at time of alert (optional)
    let breathingRate: Double?  // Breathing rate at time of alert (optional)
    var isAcknowledged: Bool    // Whether the guardian has acknowledged this alert
    var acknowledgedAt: Date?   // Acknowledgement timestamp

    init(type: AlertType, heartRate: Double? = nil, breathingRate: Double? = nil) {
        self.id             = UUID()
        self.type           = type
        self.timestamp      = Date()
        self.heartRate      = heartRate
        self.breathingRate  = breathingRate
        self.isAcknowledged = false
        self.acknowledgedAt = nil
    }

    // Restore a persisted alert with its original id and timestamp.
    init(id: UUID, type: AlertType, timestamp: Date,
         heartRate: Double?, breathingRate: Double?,
         isAcknowledged: Bool, acknowledgedAt: Date?) {
        self.id             = id
        self.type           = type
        self.timestamp      = timestamp
        self.heartRate      = heartRate
        self.breathingRate  = breathingRate
        self.isAcknowledged = isAcknowledged
        self.acknowledgedAt = acknowledgedAt
    }

    // MARK: Formatted timestamps
    var formattedDateTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d, HH:mm:ss"
        return fmt.string(from: timestamp)
    }

    var formattedDate: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return fmt.string(from: timestamp)
    }

    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }
}

// MARK: - Mock Data
extension AlertEvent {
    static func mockEvents() -> [AlertEvent] {
        let specs: [(AlertType, Double, Double, Bool)] = [
            (.heartRateLow,       Double.random(in: 32...44),  Double.random(in: 10...14), false),
            (.fall,               Double.random(in: 88...105), Double.random(in: 18...24), false),
            (.breathRateAbnormal, Double.random(in: 70...90),  Double.random(in: 26...34), true),
            (.heartRateHigh,      Double.random(in: 125...145),Double.random(in: 20...26), true),
            (.heartStop,          Double.random(in: 0...4),    Double.random(in: 0...2),   true),
        ]
        return specs.map { (type, hr, br, ack) in
            var event = AlertEvent(type: type, heartRate: hr, breathingRate: br)
            event.isAcknowledged = ack
            return event
        }
    }
}
