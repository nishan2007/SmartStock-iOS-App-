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
    let address: String?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "location_id"
        case name
        case address
        case createdAt = "created_at"
    }
}

// Used for nested Supabase joins
struct UserLocationStoreRow: Decodable {
    let locations: Store
}
