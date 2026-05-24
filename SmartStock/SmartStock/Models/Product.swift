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
    let size: String?
    let sku: String?
    let price: Double?
    let imageURL: URL?

    var displayName: String {
        displayProductName(name: name, size: size)
    }

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case name
        case size
        case sku
        case price
        case imageURL = "image_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Unknown Product"
        size = try container.decodeIfPresent(String.self, forKey: .size)
        sku = try container.decodeIfPresent(String.self, forKey: .sku)
        price = try container.decodeFlexibleDoubleIfPresent(forKey: .price)

        let rawImageURL = try container.decodeFlexibleStringIfPresent(forKey: .imageURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let rawImageURL, !rawImageURL.isEmpty {
            imageURL = URL(string: rawImageURL)
        } else {
            imageURL = nil
        }
    }
}

private extension KeyedDecodingContainer where Key == Product.CodingKeys {
    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(intValue)
        }
        if let stringValue = try? decodeIfPresent(String.self, forKey: key) {
            return Double(stringValue)
        }
        return nil
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let intValue = try? decodeIfPresent(Int.self, forKey: key) {
            return String(intValue)
        }
        if let doubleValue = try? decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }
        return nil
    }
}
