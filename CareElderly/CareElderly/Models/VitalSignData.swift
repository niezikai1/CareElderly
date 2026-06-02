// Models/VitalSignData.swift
// Vital sign data model: heart rate, breathing rate, and health status

import Foundation

// MARK: - Vital Status Enum
enum VitalStatus: String, Codable {
    case normal   // Normal range
    case warning  // Slightly high / low
    case critical // Severely abnormal

    var displayText: String {
        switch self {
        case .normal:   return "Normal"
        case .warning:  return "Abnormal"
        case .critical: return "Critical"
        }
    }

    var colorHex: String {
        switch self {
        case .normal:   return "00C853"
        case .warning:  return "FF8F00"
        case .critical: return "D32F2F"
        }
    }

    var sfSymbol: String {
        switch self {
        case .normal:   return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

// MARK: - Single Vital Sign Record
struct VitalSignData: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let heartRate: Double       // Heart rate (bpm)
    let breathingRate: Double   // Breathing rate (rpm)
    let bodyTemperature: Double? // Body temperature (°C); nil when sensor not available

    init(heartRate: Double, breathingRate: Double,
         bodyTemperature: Double? = nil, timestamp: Date = Date()) {
        self.id              = UUID()
        self.timestamp       = timestamp
        self.heartRate       = heartRate
        self.breathingRate   = breathingRate
        self.bodyTemperature = bodyTemperature
    }

    // MARK: Heart rate status
    /// Thresholds are read from UserDefaults so ThresholdSettingsView changes take effect.
    /// Falls back to clinical defaults when no value has been stored yet.
    var heartRateStatus: VitalStatus {
        let ud        = UserDefaults.standard
        let critLow  = ud.object(forKey: "hrCriticalLow")  != nil ? ud.double(forKey: "hrCriticalLow")  : 40.0
        let critHigh = ud.object(forKey: "hrCriticalHigh") != nil ? ud.double(forKey: "hrCriticalHigh") : 120.0
        let warnLow  = ud.object(forKey: "hrWarningLow")   != nil ? ud.double(forKey: "hrWarningLow")   : 50.0
        let warnHigh = ud.object(forKey: "hrWarningHigh")  != nil ? ud.double(forKey: "hrWarningHigh")  : 100.0
        if heartRate < critLow  || heartRate > critHigh { return .critical }
        if heartRate < warnLow  || heartRate > warnHigh { return .warning }
        return .normal
    }

    // MARK: Breathing rate status
    /// Thresholds mirror ThresholdSettingsView @AppStorage keys.
    var breathingRateStatus: VitalStatus {
        let ud        = UserDefaults.standard
        let critLow  = ud.object(forKey: "brCriticalLow")  != nil ? ud.double(forKey: "brCriticalLow")  : 8.0
        let critHigh = ud.object(forKey: "brCriticalHigh") != nil ? ud.double(forKey: "brCriticalHigh") : 25.0
        let warnLow  = ud.object(forKey: "brWarningLow")   != nil ? ud.double(forKey: "brWarningLow")   : 12.0
        let warnHigh = ud.object(forKey: "brWarningHigh")  != nil ? ud.double(forKey: "brWarningHigh")  : 20.0
        if breathingRate < critLow  || breathingRate > critHigh { return .critical }
        if breathingRate < warnLow  || breathingRate > warnHigh { return .warning }
        return .normal
    }

    // MARK: Body temperature status
    var bodyTemperatureStatus: VitalStatus? {
        guard let temp = bodyTemperature else { return nil }
        if temp < 35.0 || temp > 38.5 { return .critical }
        if temp < 36.0 || temp > 37.5 { return .warning }
        return .normal
    }

    /// Whether any vital is critically abnormal
    var isCritical: Bool {
        heartRateStatus == .critical || breathingRateStatus == .critical
            || bodyTemperatureStatus == .critical
    }

    /// Whether any vital has a mild warning
    var hasWarning: Bool {
        heartRateStatus == .warning || breathingRateStatus == .warning
            || bodyTemperatureStatus == .warning
    }

    // MARK: Formatted display
    var formattedTime: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return fmt.string(from: timestamp)
    }

    var heartRateText: String {
        String(format: "%.0f", heartRate)
    }

    var breathingRateText: String {
        String(format: "%.1f", breathingRate)
    }

    var bodyTemperatureText: String {
        bodyTemperature.map { String(format: "%.1f", $0) } ?? "—"
    }
}

// MARK: - Mock Data
extension VitalSignData {
    /// Generate a random normal vital sign record
    static func mockNormal() -> VitalSignData {
        VitalSignData(
            heartRate:       Double.random(in: 60...90),
            breathingRate:   Double.random(in: 14...18),
            bodyTemperature: Double.random(in: 36.2...37.2)
        )
    }

    /// Generate a mock abnormal record (for alert testing)
    static func mockAbnormal() -> VitalSignData {
        VitalSignData(
            heartRate:       Double.random(in: 25...39),
            breathingRate:   Double.random(in: 1...7),
            bodyTemperature: Double.random(in: 38.6...40.0)
        )
    }

    /// Generate a history sequence (for chart development)
    static func mockHistory(count: Int = 60) -> [VitalSignData] {
        var result: [VitalSignData] = []
        for i in 0..<count {
            let t = Date().addingTimeInterval(Double(-count + i) * 5)
            result.append(VitalSignData(
                heartRate:       Double.random(in: 62...85),
                breathingRate:   Double.random(in: 13...19),
                bodyTemperature: Double.random(in: 36.2...37.2),
                timestamp: t
            ))
        }
        return result
    }
}
