//
//  ReceiptNumberManager.swift
//  SmartStock
//

import Foundation
import Supabase

@MainActor
final class ReceiptNumberManager {
    static let shared = ReceiptNumberManager()

    private let client = supabase
    private let receiptSequencePadding = 6

    private init() {}

    func nextReceipt(for locationId: Int) async throws -> ReceiptNumber {
        let storeCode = try await fetchStoreCode(locationId: locationId)
        let deviceCode = try await fetchCurrentDeviceCode()
        let sequence = try await nextStoreSequence(locationId: locationId)

        return ReceiptNumber(
            receiptNumber: formatReceiptNumber(storeCode: storeCode, deviceId: deviceCode, sequence: sequence),
            deviceId: deviceCode,
            sequence: sequence
        )
    }

    func nextReceive(for locationId: Int) async throws -> ReceiveNumber {
        let storeCode = try await fetchStoreCode(locationId: locationId)
        let deviceCode = try await fetchCurrentDeviceCode()
        let sequence = try await nextStoreSequence(locationId: locationId)

        return ReceiveNumber(
            receiveId: formatReceiveNumber(storeCode: storeCode, deviceId: deviceCode, sequence: sequence),
            deviceId: deviceCode,
            sequence: sequence
        )
    }

    func previewSanitizedDeviceId(_ value: String) -> String {
        sanitizeCode(value)
    }

    private func fetchStoreCode(locationId: Int) async throws -> String {
        let rows: [ReceiptStoreCodeRow] = try await client
            .from("locations")
            .select("receipt_store_code")
            .eq("location_id", value: locationId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            throw ReceiptNumberManagerError.missingStoreCode
        }
        let sanitized = sanitizeCode(row.receipt_store_code)
        guard !sanitized.isEmpty else {
            throw ReceiptNumberManagerError.missingStoreCode
        }
        return sanitized
    }

    private func fetchCurrentDeviceCode() async throws -> String {
        let rows: [ReceiptDeviceCodeRow] = try await client
            .from("devices")
            .select("receipt_device_code")
            .eq("installation_id", value: DeviceService.shared.currentInstallationId())
            .eq("is_blocked", value: false)
            .eq("is_approved", value: true)
            .order("last_seen", ascending: false)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            throw ReceiptNumberManagerError.missingDeviceCode
        }
        let sanitized = sanitizeCode(row.receipt_device_code)
        guard !sanitized.isEmpty else {
            throw ReceiptNumberManagerError.missingDeviceCode
        }
        return sanitized
    }

    private func nextStoreSequence(locationId: Int) async throws -> Int {
        let rows: [ReceiptCounterRPCRow] = try await client
            .rpc(
                "next_store_receipt_counter",
                params: ReceiptCounterRPCParams(p_location_id: locationId)
            )
            .execute()
            .value

        guard let row = rows.first, row.sequence >= 1 else {
            throw ReceiptNumberManagerError.counterAdvanceFailed
        }
        return row.sequence
    }

    private func formatReceiptNumber(storeCode: String, deviceId: String, sequence: Int) -> String {
        "\(storeCode)-\(deviceId)-" + String(format: "%0\(receiptSequencePadding)d", sequence)
    }

    private func formatReceiveNumber(storeCode: String, deviceId: String, sequence: Int) -> String {
        "\(storeCode)-\(deviceId)-" + String(format: "%0\(receiptSequencePadding)d", sequence)
    }

    private func sanitizeCode(_ value: String?) -> String {
        guard let value else { return "" }
        let digits = value.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
        guard let parsed = Int(digits), parsed > 0 else { return "" }
        return String(format: "%04d", min(parsed, 9999))
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

private struct ReceiptStoreCodeRow: Decodable {
    let receipt_store_code: String
}

private struct ReceiptDeviceCodeRow: Decodable {
    let receipt_device_code: String
}

private struct ReceiptCounterRPCParams: Encodable {
    let p_location_id: Int
}

private struct ReceiptCounterRPCRow: Decodable {
    let sequence: Int
}

enum ReceiptNumberManagerError: LocalizedError {
    case missingStoreCode
    case missingDeviceCode
    case counterAdvanceFailed

    var errorDescription: String? {
        switch self {
        case .missingStoreCode:
            return "Store receipt code is missing. Set it in Company Preferences > Locations."
        case .missingDeviceCode:
            return "Device receipt code is missing. Set it in Device Management."
        case .counterAdvanceFailed:
            return "Unable to advance the store receipt counter."
        }
    }
}
