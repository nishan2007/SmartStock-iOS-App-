//
//  DeviceService.swift
//  SmartStock
//

import Foundation
import CryptoKit
import Supabase
import PostgREST
import UIKit

struct DeviceRegistrationResult {
    let device: TrackedDevice
    let sessionId: Int64
}

enum DeviceServiceError: LocalizedError {
    case blockedDevice

    var errorDescription: String? {
        switch self {
        case .blockedDevice:
            return "This device has been blocked."
        }
    }
}

final class DeviceService {
    static let shared = DeviceService()

    private enum KeychainKey {
        static let installationId = "smartstock.installation-id"
    }

    private let client = supabase
    private let decoder = JSONDecoder()

    private init() {
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = DeviceService.iso8601WithFractional.date(from: value)
                ?? DeviceService.iso8601.date(from: value)
                ?? DeviceService.timestampWithoutTimezone.date(from: value)
                ?? DeviceService.timestampWithoutTimezoneWithFractional.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported date format: \(value)"
            )
        }
    }

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let timestampWithoutTimezone: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let timestampWithoutTimezoneWithFractional: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        return formatter
    }()

    func currentInstallationId() -> String {
        if let existing = KeychainHelper.string(for: KeychainKey.installationId),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let newValue = UUID().uuidString
        KeychainHelper.set(newValue, for: KeychainKey.installationId)
        return newValue
    }

    func registerCurrentDevice(userId: Int?, storeId: Int?) async throws -> DeviceRegistrationResult {
        let info = collectDeviceInfo()

        let existing = try await fetchDevice(installationId: info.installationId)

        let device: TrackedDevice
        if let existingDevice = existing {
            if existingDevice.isBlocked {
                throw DeviceServiceError.blockedDevice
            }

            device = try await client
                .from("devices")
                .update(DeviceWritePayload(info: info, userId: userId, storeId: storeId))
                .eq("installation_id", value: info.installationId)
                .select(deviceSelectColumns)
                .single()
                .execute()
                .value
        } else {
            device = try await client
                .from("devices")
                .insert(DeviceCreatePayload(info: info, userId: userId, storeId: storeId))
                .select(deviceSelectColumns)
                .single()
                .execute()
                .value
        }

        let sessionId = try await startDeviceSession(deviceId: device.id, userId: userId, storeId: storeId)
        return DeviceRegistrationResult(device: device, sessionId: sessionId)
    }

    func fetchCurrentDevice() async throws -> TrackedDevice? {
        try await fetchDevice(installationId: currentInstallationId())
    }

    func updateCurrentDevice(deviceId: UUID, userId: Int?, storeId: Int?) async throws -> TrackedDevice {
        try await client
            .from("devices")
            .update(DeviceContextUpdatePayload(userId: userId, storeId: storeId))
            .eq("device_id", value: deviceId.uuidString)
            .select(deviceSelectColumns)
            .single()
            .execute()
            .value
    }

    func updateDeviceSession(sessionId: Int64, storeId: Int?) async throws {
        _ = try await client
            .from("device_sessions")
            .update(DeviceSessionStoreUpdatePayload(storeId: storeId))
            .eq("session_id", value: Int(sessionId))
            .execute()
    }

    func endDeviceSession(sessionId: Int64) async throws {
        _ = try await client
            .from("device_sessions")
            .update(DeviceSessionEndPayload())
            .eq("session_id", value: Int(sessionId))
            .execute()
    }

    func fetchDevices() async throws -> [TrackedDevice] {
        let response = try await client
            .from("devices")
            .select(deviceSelectColumns)
            .order("last_seen", ascending: false)
            .execute()

        return try decoder.decode([TrackedDevice].self, from: response.data)
    }

    func fetchSessions(deviceId: UUID, limit: Int = 20) async throws -> [TrackedDeviceSession] {
        let response = try await client
            .from("device_sessions")
            .select(sessionSelectColumns)
            .eq("device_id", value: deviceId.uuidString)
            .order("login_time", ascending: false)
            .limit(limit)
            .execute()

        return try decoder.decode([TrackedDeviceSession].self, from: response.data)
    }

    func updateDeviceAccess(deviceId: UUID, isApproved: Bool, isBlocked: Bool, notes: String?) async throws -> TrackedDevice {
        try await client
            .from("devices")
            .update(DeviceAccessUpdatePayload(isApproved: isApproved, isBlocked: isBlocked, statusNotes: notes))
            .eq("device_id", value: deviceId.uuidString)
            .select(deviceSelectColumns)
            .single()
            .execute()
            .value
    }

    private func startDeviceSession(deviceId: UUID, userId: Int?, storeId: Int?) async throws -> Int64 {
        let row: DeviceSessionInsertResult = try await client
            .from("device_sessions")
            .insert(DeviceSessionCreatePayload(deviceId: deviceId, userId: userId, storeId: storeId))
            .select("session_id")
            .single()
            .execute()
            .value

        return row.sessionId
    }

    private func fetchDevice(installationId: String) async throws -> TrackedDevice? {
        let devices: [TrackedDevice] = try await client
            .from("devices")
            .select(deviceSelectColumns)
            .eq("installation_id", value: installationId)
            .limit(1)
            .execute()
            .value

        return devices.first
    }

    private func collectDeviceInfo() -> DeviceInfoSnapshot {
        let device = UIDevice.current
        let installationId = currentInstallationId()
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        let versionText: String?
        if let appVersion, let buildNumber {
            versionText = "\(appVersion) (\(buildNumber))"
        } else {
            versionText = appVersion ?? buildNumber
        }
        let deviceName = device.name
        let osName = device.userInterfaceIdiom == .pad ? "iPadOS" : device.systemName
        let osVersion = device.systemVersion
        let osArch = ProcessInfo.processInfo.machineHardwareName
        let fingerprintSource = "\(installationId)|\(device.model)|\(osName)|\(osVersion)|\(Bundle.main.bundleIdentifier ?? "smartstock")"
        let fingerprint = SHA256.hash(data: Data(fingerprintSource.utf8)).compactMap { String(format: "%02x", $0) }.joined()

        return DeviceInfoSnapshot(
            installationId: installationId,
            fingerprint: fingerprint,
            deviceName: deviceName,
            hostname: nil,
            osName: osName,
            osVersion: osVersion,
            osArch: osArch,
            javaVersion: nil,
            appVersion: versionText,
            localUsername: nil,
            macAddresses: nil
        )
    }

    private var deviceSelectColumns: String {
        """
        device_id,
        installation_id,
        device_fingerprint,
        device_name,
        hostname,
        os_name,
        os_version,
        os_arch,
        java_version,
        app_version,
        local_username,
        mac_addresses,
        first_seen,
        last_seen,
        last_login_user_id,
        last_store_id,
        is_approved,
        is_blocked,
        status_notes,
        last_login_user:users!devices_last_login_user_id_fkey(full_name),
        last_store:locations(name)
        """
    }

    private var sessionSelectColumns: String {
        """
        session_id,
        device_id,
        user_id,
        store_id,
        login_time,
        logout_time,
        session_status,
        ip_address,
        notes,
        user:users(full_name),
        store:locations(name)
        """
    }
}

private struct DeviceInfoSnapshot {
    let installationId: String
    let fingerprint: String
    let deviceName: String?
    let hostname: String?
    let osName: String?
    let osVersion: String?
    let osArch: String?
    let javaVersion: String?
    let appVersion: String?
    let localUsername: String?
    let macAddresses: String?
}

private struct DeviceWritePayload: Encodable {
    let deviceFingerprint: String
    let deviceName: String?
    let hostname: String?
    let osName: String?
    let osVersion: String?
    let osArch: String?
    let javaVersion: String?
    let appVersion: String?
    let localUsername: String?
    let macAddresses: String?
    let lastLoginUserId: Int?
    let lastStoreId: Int?
    let lastSeen: String

    enum CodingKeys: String, CodingKey {
        case deviceFingerprint = "device_fingerprint"
        case deviceName = "device_name"
        case hostname
        case osName = "os_name"
        case osVersion = "os_version"
        case osArch = "os_arch"
        case javaVersion = "java_version"
        case appVersion = "app_version"
        case localUsername = "local_username"
        case macAddresses = "mac_addresses"
        case lastLoginUserId = "last_login_user_id"
        case lastStoreId = "last_store_id"
        case lastSeen = "last_seen"
    }

    init(info: DeviceInfoSnapshot, userId: Int?, storeId: Int?) {
        deviceFingerprint = info.fingerprint
        deviceName = info.deviceName
        hostname = info.hostname
        osName = info.osName
        osVersion = info.osVersion
        osArch = info.osArch
        javaVersion = info.javaVersion
        appVersion = info.appVersion
        localUsername = info.localUsername
        macAddresses = info.macAddresses
        lastLoginUserId = userId
        lastStoreId = storeId
        lastSeen = ISO8601DateFormatter().string(from: Date())
    }
}

private struct DeviceCreatePayload: Encodable {
    let installationId: String
    let deviceFingerprint: String
    let deviceName: String?
    let hostname: String?
    let osName: String?
    let osVersion: String?
    let osArch: String?
    let javaVersion: String?
    let appVersion: String?
    let localUsername: String?
    let macAddresses: String?
    let lastLoginUserId: Int?
    let lastStoreId: Int?
    let isApproved: Bool
    let isBlocked: Bool

    enum CodingKeys: String, CodingKey {
        case installationId = "installation_id"
        case deviceFingerprint = "device_fingerprint"
        case deviceName = "device_name"
        case hostname
        case osName = "os_name"
        case osVersion = "os_version"
        case osArch = "os_arch"
        case javaVersion = "java_version"
        case appVersion = "app_version"
        case localUsername = "local_username"
        case macAddresses = "mac_addresses"
        case lastLoginUserId = "last_login_user_id"
        case lastStoreId = "last_store_id"
        case isApproved = "is_approved"
        case isBlocked = "is_blocked"
    }

    init(info: DeviceInfoSnapshot, userId: Int?, storeId: Int?) {
        installationId = info.installationId
        deviceFingerprint = info.fingerprint
        deviceName = info.deviceName
        hostname = info.hostname
        osName = info.osName
        osVersion = info.osVersion
        osArch = info.osArch
        javaVersion = info.javaVersion
        appVersion = info.appVersion
        localUsername = info.localUsername
        macAddresses = info.macAddresses
        lastLoginUserId = userId
        lastStoreId = storeId
        isApproved = false
        isBlocked = false
    }
}

private struct DeviceContextUpdatePayload: Encodable {
    let lastSeen: String
    let lastLoginUserId: Int?
    let lastStoreId: Int?

    enum CodingKeys: String, CodingKey {
        case lastSeen = "last_seen"
        case lastLoginUserId = "last_login_user_id"
        case lastStoreId = "last_store_id"
    }

    init(userId: Int?, storeId: Int?) {
        lastSeen = ISO8601DateFormatter().string(from: Date())
        lastLoginUserId = userId
        lastStoreId = storeId
    }
}

private struct DeviceAccessUpdatePayload: Encodable {
    let isApproved: Bool
    let isBlocked: Bool
    let statusNotes: String?

    enum CodingKeys: String, CodingKey {
        case isApproved = "is_approved"
        case isBlocked = "is_blocked"
        case statusNotes = "status_notes"
    }
}

private struct DeviceSessionCreatePayload: Encodable {
    let deviceId: UUID
    let userId: Int?
    let storeId: Int?
    let loginTime: String
    let sessionStatus = "ACTIVE"

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case userId = "user_id"
        case storeId = "store_id"
        case loginTime = "login_time"
        case sessionStatus = "session_status"
    }

    init(deviceId: UUID, userId: Int?, storeId: Int?) {
        self.deviceId = deviceId
        self.userId = userId
        self.storeId = storeId
        self.loginTime = ISO8601DateFormatter().string(from: Date())
    }
}

private struct DeviceSessionInsertResult: Decodable {
    let sessionId: Int64

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
    }
}

private struct DeviceSessionStoreUpdatePayload: Encodable {
    let storeId: Int?

    enum CodingKeys: String, CodingKey {
        case storeId = "store_id"
    }
}

private struct DeviceSessionEndPayload: Encodable {
    let logoutTime = ISO8601DateFormatter().string(from: Date())
    let sessionStatus = "ENDED"

    enum CodingKeys: String, CodingKey {
        case logoutTime = "logout_time"
        case sessionStatus = "session_status"
    }
}

private extension ProcessInfo {
    var machineHardwareName: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
