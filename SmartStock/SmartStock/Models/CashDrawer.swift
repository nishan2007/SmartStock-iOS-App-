//
//  CashDrawer.swift
//  SmartStock
//

import Foundation

struct CashDrawer: Identifiable, Decodable, Hashable {
    static let defaultStartingCashAmount: Decimal = 20000
    static let floatDenominations: [Int] = [5000, 2000, 1000, 500, 100, 50, 20]
    static let defaultFloatMix: [Int: Int] = [1000: 8, 500: 10, 100: 50, 20: 100]

    let drawerId: Int64
    let storeId: Int
    let drawerName: String
    let drawerCode: String?
    let startingCashAmount: Decimal
    let floatMix: [Int: Int]
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?

    var id: Int64 { drawerId }

    var displayName: String {
        let code = drawerCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return code.isEmpty ? drawerName : "\(drawerName) (\(code))"
    }

    enum CodingKeys: String, CodingKey {
        case drawerId = "drawer_id"
        case storeId = "store_id"
        case drawerName = "drawer_name"
        case drawerCode = "drawer_code"
        case startingCashAmount = "starting_cash_amount"
        case floatMix = "float_mix"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drawerId = try container.decode(Int64.self, forKey: .drawerId)
        storeId = try container.decode(Int.self, forKey: .storeId)
        drawerName = try container.decode(String.self, forKey: .drawerName)
        drawerCode = try container.decodeIfPresent(String.self, forKey: .drawerCode)
        startingCashAmount = try container.decodeFlexibleDecimalIfPresent(forKey: .startingCashAmount) ?? Self.defaultStartingCashAmount
        floatMix = Self.decodeFloatMix(from: container) ?? Self.defaultFloatMix
        isActive = try container.decode(Bool.self, forKey: .isActive)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var floatMixTotalInCents: Int {
        floatMix.reduce(0) { partial, item in partial + (item.key * item.value) }
    }

    private static func decodeFloatMix(from container: KeyedDecodingContainer<CodingKeys>) -> [Int: Int]? {
        if let mix = try? container.decodeIfPresent([String: Int].self, forKey: .floatMix) {
            return normalizedFloatMix(mix)
        }
        if let text = try? container.decodeIfPresent(String.self, forKey: .floatMix),
           let data = text.data(using: .utf8),
           let mix = try? JSONDecoder().decode([String: Int].self, from: data) {
            return normalizedFloatMix(mix)
        }
        return nil
    }

    private static func normalizedFloatMix(_ raw: [String: Int]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for (denominationText, quantity) in raw {
            guard let denomination = Int(denominationText), quantity > 0 else { continue }
            result[denomination] = quantity
        }
        return result
    }
}

struct CashDrawerDeviceAssignment: Identifiable, Decodable, Hashable {
    let assignmentId: Int64
    let drawerId: Int64
    let storeId: Int
    let deviceId: UUID
    let isActive: Bool
    let notes: String?
    let assignedAt: String?
    let unassignedAt: String?
    let cashDrawers: CashDrawer?
    let devices: CashDrawerDeviceSummary?

    var id: Int64 { assignmentId }

    enum CodingKeys: String, CodingKey {
        case assignmentId = "assignment_id"
        case drawerId = "drawer_id"
        case storeId = "store_id"
        case deviceId = "device_id"
        case isActive = "is_active"
        case notes
        case assignedAt = "assigned_at"
        case unassignedAt = "unassigned_at"
        case cashDrawers = "cash_drawers"
        case devices
    }
}

struct CashDrawerDeviceSummary: Decodable, Hashable {
    let deviceId: UUID
    let deviceName: String?
    let localUsername: String?
    let osName: String?
    let osArch: String?

    var displayName: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let local = localUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if !local.isEmpty { return local }
        return osName ?? osArch ?? "Device"
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case deviceName = "device_name"
        case localUsername = "local_username"
        case osName = "os_name"
        case osArch = "os_arch"
    }
}

struct ResolvedCashDrawer {
    let drawerId: Int64
    let drawerName: String
}

enum CashDrawerError: LocalizedError {
    case missingStore
    case missingDevice
    case noAssignedDrawer

    var errorDescription: String? {
        switch self {
        case .missingStore:
            return "Select a store before using cash drawer features."
        case .missingDevice:
            return "This device is not registered yet."
        case .noAssignedDrawer:
            return "No cash drawer assigned to this device for this store."
        }
    }
}

private extension KeyedDecodingContainer where Key == CashDrawer.CodingKeys {
    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let value = try? decodeIfPresent(Decimal.self, forKey: key) {
            return value
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: stringValue)
        }
        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return Decimal(doubleValue)
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return Decimal(intValue)
        }
        return nil
    }
}
