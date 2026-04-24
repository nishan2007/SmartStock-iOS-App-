//
//  Product.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation

struct Product: Decodable, Identifiable {
    let id: Int
    let name: String
    let sku: String?
    let price: Double?

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case name
        case sku
        case price
    }
}
