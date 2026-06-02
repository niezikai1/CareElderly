// Services/MQTTService.swift
// Minimal MQTT 3.1.1 client built on Network.framework.
// Zero third-party dependencies — uses only Apple frameworks.
//
// Supports: CONNECT · SUBSCRIBE · PUBLISH receive (QoS 0/1) · PINGREQ/RESP
// Automatically reconnects with exponential back-off on disconnect.

import Foundation
import Network
import Combine

// MARK: - MQTTService

class MQTTService: ObservableObject {

    // MARK: Published state
    @Published var connectionStatus:  ConnectionStatus = .disconnected
    @Published var lastVitalSign:     VitalSignData?
    @Published var pendingAlertEvent: AlertEvent?

    var autoReconnect = true

    // MARK: Private
    private var connection:      NWConnection?
    private var currentHost:     String  = ""
    private var currentPort:     UInt16  = 1883
    private var currentTopic:    String  = "vitals"
    private var currentUsername: String  = ""
    private var currentPassword: String  = ""
    private var currentUseTLS:   Bool    = false

    private var rxBuf = Data()
    private var pingTimer: AnyCancellable?

    private var reconnectAttempts = 0
    private let maxAttempts       = 20
    private let baseDelay: TimeInterval = 3
    private let maxDelay:  TimeInterval = 60

    private let clientID = "careelderly-\(UUID().uuidString.prefix(8))"

    // Dedicated serial queue for all network I/O and packet parsing.
    // Keeps the main thread free for UI events.
    private let netQueue = DispatchQueue(label: "com.careelderly.mqtt.net", qos: .userInitiated)

    // MARK: - Public API

    func connect(host: String, port: UInt16 = 1883, topic: String,
                 username: String = "", password: String = "", useTLS: Bool = false) {
        disconnect(shouldReconnect: false)
        currentHost     = host
        currentPort     = port
        currentTopic    = topic
        currentUsername = username
        currentPassword = password
        currentUseTLS   = useTLS
        reconnectAttempts = 0
        autoReconnect = true
        openConnection()
    }

    func connectFromSavedSettings() {
        let ud       = UserDefaults.standard
        let host     = ud.string(forKey: "mqttHost")     ?? ""
        let portInt  = ud.integer(forKey: "mqttPort")
        let port     = UInt16(portInt > 0 ? portInt : 1883)
        let topic    = ud.string(forKey: "mqttTopic")    ?? "vitals"
        let username = ud.string(forKey: "mqttUsername") ?? ""
        let password = ud.string(forKey: "mqttPassword") ?? ""
        let useTLS   = ud.bool(forKey: "mqttUseTLS")
        guard !host.isEmpty else { return }
        connect(host: host, port: port, topic: topic,
                username: username, password: password, useTLS: useTLS)
    }

    func disconnect(shouldReconnect: Bool = false) {
        if !shouldReconnect { autoReconnect = false }
        stopPing()
        connection?.cancel()
        connection = nil
        netQueue.async { self.rxBuf.removeAll() }
        if !shouldReconnect {
            DispatchQueue.main.async { self.connectionStatus = .disconnected }
        }
    }

    // MARK: - Connection

    private func openConnection() {
        guard !currentHost.isEmpty else { return }
        DispatchQueue.main.async { self.connectionStatus = .connecting }

        let conn = NWConnection(
            host: NWEndpoint.Host(currentHost),
            port: NWEndpoint.Port(rawValue: currentPort)!,
            using: currentUseTLS ? .tls : .tcp
        )
        connection = conn
        conn.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.txConnect()
                self.receiveLoop()
            case .failed(let err):
                DispatchQueue.main.async {
                    self.handleDisconnect(reason: err.localizedDescription)
                }
            case .cancelled:
                break
            default:
                break
            }
        }
        conn.start(queue: netQueue)
    }

    private func handleDisconnect(reason: String = "") {
        guard connection != nil else { return }

        stopPing()

        connection?.cancel()
        connection = nil
        netQueue.async { self.rxBuf.removeAll() }

        guard autoReconnect, reconnectAttempts < maxAttempts else {
            connectionStatus = .disconnected
            return
        }
        
        let delay = min(baseDelay * pow(2.0, Double(reconnectAttempts)), maxDelay)
        reconnectAttempts += 1
        print("🔄 MQTT reconnect in \(Int(delay))s (attempt \(reconnectAttempts))")
        connectionStatus = .connecting
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.openConnection()
        }
    }

    // MARK: - TX: MQTT packet construction

    private func txConnect() {
        var body = Data()
        mqttAppendString("MQTT", to: &body)             // Protocol name

        // Connect flags: clean session (0x02) + username/password bits when present
        let hasCredentials = !currentUsername.isEmpty
        let connectFlags: UInt8 = hasCredentials ? 0xC2 : 0x02
        body.append(contentsOf: [
            0x04,          // Version: 3.1.1
            connectFlags,
            0x00, 0x3C     // Keep-alive: 60 s
        ])

        mqttAppendString(clientID, to: &body)
        if hasCredentials {
            mqttAppendString(currentUsername, to: &body)
            mqttAppendString(currentPassword, to: &body)
        }
        tx(mqttFrame(type: 0x10, body: body))
    }

    private func txSubscribe() {
        var body = Data([0x00, 0x01])                    // Packet ID = 1
        mqttAppendString(currentTopic, to: &body)
        body.append(0x01)                                // QoS 1
        tx(mqttFrame(type: 0x82, body: body))
    }

    private func txPubAck(packetID: UInt16) {
        tx(mqttFrame(type: 0x40, body: Data([
            UInt8(packetID >> 8), UInt8(packetID & 0xFF)
        ])))
    }

    private func txPingReq() {
        tx(Data([0xC0, 0x00]))
    }

    // MARK: - RX: Receive loop

    private func receiveLoop() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            // Runs on netQueue — keep packet parsing off the main thread.
            if let data, !data.isEmpty {
                self.rxBuf += data
                self.drainBuffer()
            }
            if error != nil || done {
                DispatchQueue.main.async { self.handleDisconnect() }
            } else {
                self.receiveLoop()
            }
        }
    }

    private func drainBuffer() {
        while let (firstByte, body, consumed) = parseNextPacket(from: rxBuf) {
            rxBuf.removeFirst(consumed)
            handlePacket(type: firstByte >> 4, flags: firstByte & 0x0F, body: body)
        }
    }

    /// Parse the next complete MQTT packet from the front of `buf`.
    /// Returns (firstHeaderByte, bodyData, totalBytesConsumed) or nil if incomplete.
    /// Uses startIndex-relative indexing so sliced Data (after removeFirst) works correctly.
    private func parseNextPacket(from buf: Data) -> (UInt8, Data, Int)? {
        guard buf.count >= 2 else { return nil }
        let base = buf.startIndex
        var pos = base + 1
        var remaining = 0
        var multiplier = 1
        repeat {
            guard pos < buf.endIndex else { return nil }
            let byte = Int(buf[pos]); pos += 1
            remaining += (byte & 0x7F) * multiplier
            multiplier <<= 7
            if byte & 0x80 == 0 { break }
        } while multiplier <= (128 * 128 * 128)
        guard buf.endIndex >= pos + remaining else { return nil }
        return (buf[base], Data(buf[pos ..< pos + remaining]), (pos - base) + remaining)
    }

    // MARK: - Packet dispatch

    private func handlePacket(type: UInt8, flags: UInt8, body: Data) {
        switch type {
        case 2:    // CONNACK
            handleConnAck(body: body)
        case 3:    // PUBLISH
            handlePublish(flags: flags, body: body)
        case 9:    // SUBACK
            print("✅ MQTT subscribed to: \(currentTopic)")
        case 13:   // PINGRESP
            break
        default:
            break
        }
    }

    private func handleConnAck(body: Data) {
        guard body.count >= 2 else { return }
        let returnCode = body[1]
        guard returnCode == 0 else {
            let msg = "MQTT broker refused: code \(returnCode)"
            DispatchQueue.main.async { self.connectionStatus = .error(message: msg) }
            return
        }
        txSubscribe()
        // Dispatch @Published updates and timer setup to main.
        DispatchQueue.main.async {
            self.reconnectAttempts = 0
            self.connectionStatus = .connected(serverURL: "\(self.currentHost):\(self.currentPort)")
            self.startPing()
        }
    }

    private func handlePublish(flags: UInt8, body: Data) {
        guard body.count >= 2 else { return }
        let topicLen = Int(body[0]) << 8 | Int(body[1])
        guard body.count >= 2 + topicLen else { return }

        let qos = (flags >> 1) & 0x03
        var payloadStart = 2 + topicLen
        if qos > 0 {
            // QoS 1/2: send PUBACK before processing
            guard payloadStart + 2 <= body.count else { return }
            let packetID = UInt16(body[payloadStart]) << 8 | UInt16(body[payloadStart + 1])
            if qos == 1 { txPubAck(packetID: packetID) }
            payloadStart += 2
        }

        guard payloadStart <= body.count,
              let msgStr = String(data: body[payloadStart...], encoding: .utf8)
        else { return }

        processMessage(msgStr)
    }

    // MARK: - Message processing

    private func processMessage(_ json: String) {
        guard let raw = json.data(using: .utf8),
              let msg = try? JSONDecoder().decode(ServerMessage.self, from: raw)
        else {
            print("⚠️ MQTT decode error for: \(json)")
            return
        }

        if msg.type == "alert" {
            guard let rawType   = msg.eventType,
                  let alertType = AlertType(rawValue: rawType) else {
                print("⚠️ Unknown alert event_type: \(msg.eventType ?? "nil")"); return
            }
            let event = AlertEvent(type: alertType,
                                   heartRate: msg.heartRate,
                                   breathingRate: msg.breathingRate)
            DispatchQueue.main.async { self.pendingAlertEvent = event }
            return
        }

        guard let hr = msg.heartRate, let br = msg.breathingRate else {
            print("⚠️ Vital-sign packet missing hr/br fields in: \(json)"); return
        }
        let ts = msg.timestampMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date()
        let vital = VitalSignData(heartRate: hr, breathingRate: br,
                                  bodyTemperature: msg.bodyTemperature, timestamp: ts)
        DispatchQueue.main.async { self.lastVitalSign = vital }
    }

    // MARK: - Ping keepalive

    private func startPing() {
        stopPing()
        pingTimer = Timer.publish(every: 50, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.txPingReq() }
    }

    private func stopPing() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    // MARK: - Low-level helpers

    private func tx(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Build an MQTT fixed header + variable-length remaining-length + body.
    private func mqttFrame(type: UInt8, body: Data) -> Data {
        var packet = Data([type])
        var len = body.count
        repeat {
            var byte = UInt8(len & 0x7F)
            len >>= 7
            if len > 0 { byte |= 0x80 }
            packet.append(byte)
        } while len > 0
        packet += body
        return packet
    }

    /// Append a UTF-8 string with a 2-byte big-endian length prefix (MQTT string encoding).
    private func mqttAppendString(_ s: String, to data: inout Data) {
        let bytes = s.data(using: .utf8) ?? Data()
        data.append(UInt8(bytes.count >> 8))
        data.append(UInt8(bytes.count & 0xFF))
        data += bytes
    }
}
