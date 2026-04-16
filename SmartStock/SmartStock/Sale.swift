//
//  Sale.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//


import Foundation

struct SaleUser: Decodable {
    let full_name: String?
}

struct SaleLocation: Decodable {
    let name: String?
}

struct Sale: Decodable, Identifiable {
    let sale_id: Int
    let total_amount: Double?
    let status: String?
    let transaction_source: String?
    let created_at: String?
    let users: SaleUser?
    let locations: SaleLocation?

    var id: Int { sale_id }

    var cashierName: String {
        users?.full_name ?? "Unknown Cashier"
    }

    var storeName: String {
        locations?.name ?? "Unknown Store"
    }

    var totalText: String {
        String(format: "$%.2f", total_amount ?? 0)
    }

    var sourceText: String {
        switch transaction_source?.lowercased() {
        case "mobile_app":
            return "Mobile App"
        case "desktop_app":
            return "Desktop App"
        case let value? where !value.isEmpty:
            return value.replacingOccurrences(of: "_", with: " ").capitalized
        default:
            return "Unknown Source"
        }
    }

    var createdAtText: String {
        Self.displayFormatter.string(from: Self.parseDate(created_at) ?? Date())
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func parseDate(_ rawValue: String?) -> Date? {
        guard let rawValue, !rawValue.isEmpty else { return nil }

        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: rawValue) {
            return date
        }

        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        if let date = isoStandard.date(from: rawValue) {
            return date
        }

        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = localFormatter.date(from: rawValue) {
            return date
        }

        let localFormatterWithFraction = DateFormatter()
        localFormatterWithFraction.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        localFormatterWithFraction.locale = Locale(identifier: "en_US_POSIX")
        return localFormatterWithFraction.date(from: rawValue)
    }
}

struct SaleItemProduct: Decodable {
    let name: String?
}

struct SaleItem: Decodable, Identifiable {
    let sale_item_id: Int
    let quantity: Int
    let unit_price: Double?
    let products: SaleItemProduct?

    var id: Int { sale_item_id }

    var productName: String {
        products?.name ?? "Unknown Product"
    }

    var unitPriceText: String {
        String(format: "$%.2f", unit_price ?? 0)
    }

    var lineTotal: Double {
        Double(quantity) * (unit_price ?? 0)
    }

    var lineTotalText: String {
        String(format: "$%.2f", lineTotal)
    }
}
