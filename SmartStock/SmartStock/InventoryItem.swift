//
//  InventoryItem.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation

struct InventoryItem: Identifiable, Hashable {
    let id: String
    let productId: Int
    let name: String
    let sku: String
    let barcode: String?
    let additionalBarcodes: [String]
    let price: Decimal
    let quantity: Int
    let reorderLevel: Int
    let locationId: Int
    let locationName: String
    let categoryName: String?
    let vendorName: String?
    let itemDescription: String?
    let productType: ProductType
    let costPrice: Decimal?
    let imageURL: URL?
    let updatedAt: Date?

    init(
        id: String? = nil,
        productId: Int,
        name: String,
        sku: String,
        barcode: String? = nil,
        additionalBarcodes: [String] = [],
        price: Decimal,
        quantity: Int,
        reorderLevel: Int,
        locationId: Int,
        locationName: String,
        categoryName: String? = nil,
        vendorName: String? = nil,
        itemDescription: String? = nil,
        productType: ProductType = .inventory,
        costPrice: Decimal? = nil,
        imageURL: URL? = nil,
        updatedAt: Date? = nil
    ) {
        self.productId = productId
        self.id = id ?? "\(productId)-\(locationId)"
        self.name = name
        self.sku = sku
        self.barcode = barcode
        self.additionalBarcodes = additionalBarcodes
        self.price = price
        self.quantity = quantity
        self.reorderLevel = reorderLevel
        self.locationId = locationId
        self.locationName = locationName
        self.categoryName = categoryName
        self.vendorName = vendorName
        self.itemDescription = itemDescription
        self.productType = productType
        self.costPrice = costPrice
        self.imageURL = imageURL
        self.updatedAt = updatedAt
    }

    var status: InventoryStockStatus {
        guard productType == .inventory else { return .notTracked }
        if quantity < 0 { return .negative }
        if quantity == 0 { return .outOfStock }
        if quantity <= reorderLevel { return .lowStock }
        return .inStock
    }

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: price as NSDecimalNumber) ?? "$0.00"
    }

    var quantityText: String { "\(quantity)" }
    var reorderLevelText: String { "\(reorderLevel)" }

    var formattedCostPrice: String {
        guard let costPrice else { return "—" }
        return InventoryItem.currencyFormatter.string(from: costPrice as NSDecimalNumber) ?? "$0.00"
    }

    private static let currencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter
    }()
}

enum InventoryStockStatus: String, CaseIterable, Hashable {
    case inStock = "In Stock"
    case lowStock = "Low Stock"
    case outOfStock = "Out of Stock"
    case negative = "Negative"
    case notTracked = "Not Tracked"
}

enum ProductType: String, CaseIterable, Identifiable, Codable, Hashable {
    case inventory = "INVENTORY"
    case service = "SERVICE"
    case nonInventory = "NON_INVENTORY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .inventory:
            return "Inventory"
        case .service:
            return "Service"
        case .nonInventory:
            return "Non Inventory"
        }
    }

    static func fromDatabaseValue(_ value: String?) -> ProductType {
        guard let value else { return .inventory }
        return ProductType(rawValue: value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) ?? .inventory
    }
}
