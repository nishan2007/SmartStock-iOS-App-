//
//  TrackedDevice.swift
//  SmartStock
//

import Foundation

struct TrackedDevice: Identifiable, Decodable, Equatable {
    let id: UUID
    let installationId: String
    let deviceFingerprint: String?
    let deviceName: String?
    let hostname: String?
    let osName: String?
    let osVersion: String?
    let osArch: String?
    let javaVersion: String?
    let appVersion: String?
    let localUsername: String?
    let macAddresses: String?
    let firstSeen: Date
    let lastSeen: Date
    let lastLoginUserId: Int?
    let lastLoginUserName: String?
    let lastStoreId: Int?
    let lastStoreName: String?
    let assignedLocationId: Int?
    let isApproved: Bool
    let isBlocked: Bool
    let notes: String?

    var modelName: String {
        DeviceModelNameMapper.displayName(for: osArch, platformName: osName)
    }

    var modelIdentifier: String {
        let trimmedIdentifier = osArch?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIdentifier.isEmpty ? "Unknown" : trimmedIdentifier
    }

    enum CodingKeys: String, CodingKey {
        case id = "device_id"
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
        case firstSeen = "first_seen"
        case lastSeen = "last_seen"
        case lastLoginUserId = "last_login_user_id"
        case lastStoreId = "last_store_id"
        case assignedLocationId = "assigned_location_id"
        case isApproved = "is_approved"
        case isBlocked = "is_blocked"
        case notes
        case statusNotes = "status_notes"
        case lastLoginUser = "last_login_user"
        case lastStore = "last_store"
    }

    init(
        id: UUID,
        installationId: String,
        deviceFingerprint: String?,
        deviceName: String?,
        hostname: String?,
        osName: String?,
        osVersion: String?,
        osArch: String?,
        javaVersion: String?,
        appVersion: String?,
        localUsername: String?,
        macAddresses: String?,
        firstSeen: Date,
        lastSeen: Date,
        lastLoginUserId: Int?,
        lastLoginUserName: String?,
        lastStoreId: Int?,
        lastStoreName: String?,
        assignedLocationId: Int?,
        isApproved: Bool,
        isBlocked: Bool,
        notes: String?
    ) {
        self.id = id
        self.installationId = installationId
        self.deviceFingerprint = deviceFingerprint
        self.deviceName = deviceName
        self.hostname = hostname
        self.osName = osName
        self.osVersion = osVersion
        self.osArch = osArch
        self.javaVersion = javaVersion
        self.appVersion = appVersion
        self.localUsername = localUsername
        self.macAddresses = macAddresses
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.lastLoginUserId = lastLoginUserId
        self.lastLoginUserName = lastLoginUserName
        self.lastStoreId = lastStoreId
        self.lastStoreName = lastStoreName
        self.assignedLocationId = assignedLocationId
        self.isApproved = isApproved
        self.isBlocked = isBlocked
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        installationId = try container.decode(String.self, forKey: .installationId)
        deviceFingerprint = try container.decodeIfPresent(String.self, forKey: .deviceFingerprint)
        deviceName = try container.decodeIfPresent(String.self, forKey: .deviceName)
        hostname = try container.decodeIfPresent(String.self, forKey: .hostname)
        osName = try container.decodeIfPresent(String.self, forKey: .osName)
        osVersion = try container.decodeIfPresent(String.self, forKey: .osVersion)
        osArch = try container.decodeIfPresent(String.self, forKey: .osArch)
        javaVersion = try container.decodeIfPresent(String.self, forKey: .javaVersion)
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
        localUsername = try container.decodeIfPresent(String.self, forKey: .localUsername)
        macAddresses = try container.decodeIfPresent(String.self, forKey: .macAddresses)
        firstSeen = try container.decode(Date.self, forKey: .firstSeen)
        lastSeen = try container.decode(Date.self, forKey: .lastSeen)
        lastLoginUserId = try container.decodeIfPresent(Int.self, forKey: .lastLoginUserId)
        lastStoreId = try container.decodeIfPresent(Int.self, forKey: .lastStoreId)
        assignedLocationId = try container.decodeIfPresent(Int.self, forKey: .assignedLocationId)
        isApproved = try container.decode(Bool.self, forKey: .isApproved)
        isBlocked = try container.decode(Bool.self, forKey: .isBlocked)
        notes = try container.decodeIfPresent(String.self, forKey: .statusNotes)
            ?? container.decodeIfPresent(String.self, forKey: .notes)

        let lastLoginUser = try container.decodeIfPresent(DeviceUserSummary.self, forKey: .lastLoginUser)
        lastLoginUserName = lastLoginUser?.fullName

        let lastStore = try container.decodeIfPresent(DeviceStoreSummary.self, forKey: .lastStore)
        lastStoreName = lastStore?.name
    }

    func updatingApproval(_ approved: Bool, blocked: Bool, notes: String?) -> TrackedDevice {
        TrackedDevice(
            id: id,
            installationId: installationId,
            deviceFingerprint: deviceFingerprint,
            deviceName: deviceName,
            hostname: hostname,
            osName: osName,
            osVersion: osVersion,
            osArch: osArch,
            javaVersion: javaVersion,
            appVersion: appVersion,
            localUsername: localUsername,
            macAddresses: macAddresses,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            lastLoginUserId: lastLoginUserId,
            lastLoginUserName: lastLoginUserName,
            lastStoreId: lastStoreId,
            lastStoreName: lastStoreName,
            assignedLocationId: assignedLocationId,
            isApproved: approved,
            isBlocked: blocked,
            notes: notes
        )
    }

    func updatingStore(_ store: Store?) -> TrackedDevice {
        TrackedDevice(
            id: id,
            installationId: installationId,
            deviceFingerprint: deviceFingerprint,
            deviceName: deviceName,
            hostname: hostname,
            osName: osName,
            osVersion: osVersion,
            osArch: osArch,
            javaVersion: javaVersion,
            appVersion: appVersion,
            localUsername: localUsername,
            macAddresses: macAddresses,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            lastLoginUserId: lastLoginUserId,
            lastLoginUserName: lastLoginUserName,
            lastStoreId: store?.id,
            lastStoreName: store?.name,
            assignedLocationId: assignedLocationId,
            isApproved: isApproved,
            isBlocked: isBlocked,
            notes: notes
        )
    }
}

private enum DeviceModelNameMapper {
    static func displayName(for identifier: String?, platformName: String?) -> String {
        let trimmedIdentifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !trimmedIdentifier.isEmpty else {
            return platformName ?? "Unknown Device"
        }

        if let mappedName = modelNames[trimmedIdentifier] {
            return mappedName
        }

        if ["i386", "x86_64", "arm64"].contains(trimmedIdentifier) {
            let platform = platformName?.isEmpty == false ? platformName! : "iOS"
            return "\(platform) Simulator"
        }

        return trimmedIdentifier
    }

    private static let modelNames: [String: String] = [
        "iPhone12,1": "iPhone 11",
        "iPhone12,3": "iPhone 11 Pro",
        "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2nd generation)",
        "iPhone13,1": "iPhone 12 mini",
        "iPhone13,2": "iPhone 12",
        "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPhone18,1": "iPhone 17 Pro",
        "iPhone18,2": "iPhone 17 Pro Max",
        "iPhone18,3": "iPhone 17",
        "iPhone18,4": "iPhone Air",
        "iPhone18,5": "iPhone 17e",
        "iPad13,16": "iPad Air (5th generation)",
        "iPad13,17": "iPad Air (5th generation)",
        "iPad14,1": "iPad mini (6th generation)",
        "iPad14,2": "iPad mini (6th generation)",
        "iPad14,3": "iPad Pro 11-inch (4th generation)",
        "iPad14,4": "iPad Pro 11-inch (4th generation)",
        "iPad14,5": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,6": "iPad Pro 12.9-inch (6th generation)",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 11-inch (M2)",
        "iPad14,10": "iPad Air 13-inch (M2)",
        "iPad14,11": "iPad Air 13-inch (M2)",
        "iPad15,3": "iPad Air 11-inch (M3)",
        "iPad15,4": "iPad Air 11-inch (M3)",
        "iPad15,5": "iPad Air 13-inch (M3)",
        "iPad15,6": "iPad Air 13-inch (M3)",
        "iPad15,7": "iPad (A16)",
        "iPad15,8": "iPad (A16)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 11-inch (M4)",
        "iPad16,5": "iPad Pro 13-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)"
    ]
}

private struct DeviceUserSummary: Decodable {
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

private struct DeviceStoreSummary: Decodable {
    let name: String?
}

struct TrackedDeviceSession: Identifiable, Decodable {
    let id: Int64
    let deviceId: UUID
    let userId: Int?
    let userName: String?
    let storeId: Int?
    let storeName: String?
    let loginTime: Date
    let logoutTime: Date?
    let sessionStatus: String
    let ipAddress: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case deviceId = "device_id"
        case userId = "user_id"
        case storeId = "store_id"
        case loginTime = "login_time"
        case logoutTime = "logout_time"
        case sessionStatus = "session_status"
        case ipAddress = "ip_address"
        case notes
        case user
        case store
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int64.self, forKey: .id)
        deviceId = try container.decode(UUID.self, forKey: .deviceId)
        userId = try container.decodeIfPresent(Int.self, forKey: .userId)
        storeId = try container.decodeIfPresent(Int.self, forKey: .storeId)
        loginTime = try container.decode(Date.self, forKey: .loginTime)
        logoutTime = try container.decodeIfPresent(Date.self, forKey: .logoutTime)
        sessionStatus = try container.decode(String.self, forKey: .sessionStatus)
        ipAddress = try container.decodeIfPresent(String.self, forKey: .ipAddress)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        let user = try container.decodeIfPresent(DeviceUserSummary.self, forKey: .user)
        userName = user?.fullName

        let store = try container.decodeIfPresent(DeviceStoreSummary.self, forKey: .store)
        storeName = store?.name
    }
}
