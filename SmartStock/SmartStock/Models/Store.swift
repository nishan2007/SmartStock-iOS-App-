//
//  CreateStore.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//
//
//  Store.swift
//  SmartStock
//

import Foundation

struct Store: Decodable, Identifiable, Equatable, Hashable {
    let id: Int
    let name: String
    let receiptStoreCode: String?
    let address: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "location_id"
        case name
        case receiptStoreCode = "receipt_store_code"
        case address
        case createdAt = "created_at"
    }

    init(
        id: Int,
        name: String,
        receiptStoreCode: String? = nil,
        address: String? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.receiptStoreCode = receiptStoreCode
        self.address = address
        self.createdAt = createdAt
    }
}

// Used for nested Supabase joins
struct UserLocationStoreRow: Decodable {
    let locations: Store
}

struct EmployeeStoreAssignmentRow: Decodable {
    let location_id: Int
    let locations: Store?
}
