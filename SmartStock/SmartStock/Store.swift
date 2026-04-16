//
//  CreateStore.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation

struct Store: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "location_id"
        case name
    }
}

struct UserLocationStoreRow: Decodable {
    let locations: Store
}
