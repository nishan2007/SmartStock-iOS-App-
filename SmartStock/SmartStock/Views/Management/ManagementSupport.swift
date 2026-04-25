//
//  ManagementSupport.swift
//  SmartStock
//

import Foundation

struct VendorAdminRow: Decodable, Identifiable {
    let id: Int
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id = "vendor_id"
        case name
        case isActive = "is_active"
    }
}

struct VendorWritePayload: Encodable {
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isActive = "is_active"
    }
}

struct LocationWritePayload: Encodable {
    let name: String
    let address: String?
}

struct ReceivingHistoryProduct: Decodable {
    let name: String?
}

struct ReceivingHistoryLocation: Decodable {
    let name: String?
}

struct ReceivingHistoryRow: Decodable, Identifiable {
    let id: Int
    let changeQty: Int
    let reason: String
    let note: String?
    let createdAt: String?
    let receiveId: String?
    let userName: String?
    let products: ReceivingHistoryProduct?
    let locations: ReceivingHistoryLocation?

    enum CodingKeys: String, CodingKey {
        case id = "movement_id"
        case changeQty = "change_qty"
        case reason
        case note
        case createdAt = "created_at"
        case receiveId = "receive_id"
        case userName = "user_name"
        case products
        case locations
    }

    var productName: String { products?.name ?? "Unknown Product" }
    var storeName: String { locations?.name ?? "Unknown Store" }
    var quantityText: String { changeQty > 0 ? "+\(changeQty)" : "\(changeQty)" }

    var sourceText: String {
        switch reason.uppercased() {
        case "RECEIVE":
            return "Receiving"
        case "INVENTORY_ENTRY":
            return transferIdFromNote == nil ? "Receiving" : "Store Transfer"
        default:
            return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var receiveIdText: String? {
        let trimmed = receiveId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var enteredByText: String? {
        let trimmed = userName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    var noteText: String? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return nil
        }

        if reason.uppercased() == "INVENTORY_ENTRY",
           let transferId = transferIdFromNote {
            return "Transfer #\(transferId)"
        }

        return trimmed
    }

    private var transferIdFromNote: String? {
        guard let note else { return nil }
        guard let range = note.range(of: "transfer_id=") else { return nil }
        let suffix = note[range.upperBound...]
        let transferId = suffix.prefix { $0.isNumber }
        return transferId.isEmpty ? nil : String(transferId)
    }
}

func normalizedValue(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
