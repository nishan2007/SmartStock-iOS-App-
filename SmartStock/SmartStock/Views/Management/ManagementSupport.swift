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
    let products: ReceivingHistoryProduct?
    let locations: ReceivingHistoryLocation?

    enum CodingKeys: String, CodingKey {
        case id = "movement_id"
        case changeQty = "change_qty"
        case reason
        case note
        case createdAt = "created_at"
        case products
        case locations
    }

    var productName: String { products?.name ?? "Unknown Product" }
    var storeName: String { locations?.name ?? "Unknown Store" }
    var quantityText: String { changeQty > 0 ? "+\(changeQty)" : "\(changeQty)" }
    var reasonText: String { reason.replacingOccurrences(of: "_", with: " ").capitalized }
}

func normalizedValue(_ value: String) -> String? {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}
