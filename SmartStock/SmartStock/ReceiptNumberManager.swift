//
//  ReceiptNumberManager.swift
//  SmartStock
//

import Foundation
import UIKit

@MainActor
final class ReceiptNumberManager {
    static let shared = ReceiptNumberManager()

    private enum StorageKey {
        static let receiptDeviceId = "smartstock.receipt-device-id"
        static let nextReceiptSequencePrefix = "smartstock.next-receipt-sequence"
        static let nextReceiveSequencePrefix = "smartstock.next-receive-sequence"
    }

    private let defaults: UserDefaults
    private let receiptSequencePadding = 6

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func nextReceipt(for locationId: Int) -> ReceiptNumber {
        let deviceId = currentDeviceId()
        let storeCode = formatStoreCode(locationId)
        let sequenceKey = "\(StorageKey.nextReceiptSequencePrefix).\(storeCode).\(deviceId)"
        let sequence = max(defaults.integer(forKey: sequenceKey), 1)

        defaults.set(sequence + 1, forKey: sequenceKey)

        return ReceiptNumber(
            receiptNumber: formatReceiptNumber(storeCode: storeCode, deviceId: deviceId, sequence: sequence),
            deviceId: deviceId,
            sequence: sequence
        )
    }

    func nextReceive(for locationId: Int) -> ReceiveNumber {
        let deviceId = currentDeviceId()
        let storeCode = formatStoreCode(locationId)
        let sequenceKey = "\(StorageKey.nextReceiveSequencePrefix).\(storeCode).\(deviceId)"
        let sequence = max(defaults.integer(forKey: sequenceKey), 1)

        defaults.set(sequence + 1, forKey: sequenceKey)

        return ReceiveNumber(
            receiveId: formatReceiveNumber(storeCode: storeCode, deviceId: deviceId, sequence: sequence),
            deviceId: deviceId,
            sequence: sequence
        )
    }

    func currentDeviceId() -> String {
        if let existing = KeychainHelper.string(for: StorageKey.receiptDeviceId) {
            let sanitized = sanitizeDeviceId(existing)
            if !sanitized.isEmpty {
                if sanitized != existing {
                    KeychainHelper.set(sanitized, for: StorageKey.receiptDeviceId)
                }
                return sanitized
            }
        }

        let fallback = sanitizeDeviceId("POS-\(UIDevice.current.name)")
        let deviceId = fallback.isEmpty ? "POS-LOCAL" : fallback
        KeychainHelper.set(deviceId, for: StorageKey.receiptDeviceId)
        return deviceId
    }

    func previewSanitizedDeviceId(_ value: String) -> String {
        sanitizeDeviceId(value)
    }

    @discardableResult
    func updateDeviceId(_ value: String) throws -> String {
        let sanitized = sanitizeDeviceId(value)
        guard !sanitized.isEmpty else {
            throw ReceiptNumberManagerError.invalidDeviceName
        }

        KeychainHelper.set(sanitized, for: StorageKey.receiptDeviceId)
        return sanitized
    }

    private func formatStoreCode(_ locationId: Int) -> String {
        String(format: "S%03d", locationId)
    }

    private func formatReceiptNumber(storeCode: String, deviceId: String, sequence: Int) -> String {
        "R-\(storeCode)-\(deviceId)-" + String(format: "%0\(receiptSequencePadding)d", sequence)
    }

    private func formatReceiveNumber(storeCode: String, deviceId: String, sequence: Int) -> String {
        "RCV-\(storeCode)-\(deviceId)-" + String(format: "%0\(receiptSequencePadding)d", sequence)
    }

    private func sanitizeDeviceId(_ value: String?) -> String {
        guard let value else { return "" }

        let uppercased = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !uppercased.isEmpty else { return "" }

        let replaced = uppercased.replacingOccurrences(
            of: "[^A-Z0-9-]+",
            with: "-",
            options: .regularExpression
        )
        let collapsed = replaced.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)

        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

struct ReceiptNumber: Equatable {
    let receiptNumber: String
    let deviceId: String
    let sequence: Int
}

struct ReceiveNumber: Equatable {
    let receiveId: String
    let deviceId: String
    let sequence: Int
}

enum ReceiptNumberManagerError: LocalizedError {
    case invalidDeviceName

    var errorDescription: String? {
        switch self {
        case .invalidDeviceName:
            return "Enter a device name with at least one letter or number."
        }
    }
}
