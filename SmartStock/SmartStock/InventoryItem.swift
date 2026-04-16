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
    let price: Decimal
    let quantity: Int
    let reorderLevel: Int
    let locationId: Int
    let locationName: String
    let categoryName: String?
    let itemDescription: String?
    let updatedAt: Date?

    init(
        id: String? = nil,
        productId: Int,
        name: String,
        sku: String,
        barcode: String? = nil,
        price: Decimal,
        quantity: Int,
        reorderLevel: Int,
        locationId: Int,
        locationName: String,
        categoryName: String? = nil,
        itemDescription: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.productId = productId
        self.id = id ?? "\(productId)-\(locationId)"
        self.name = name
        self.sku = sku
        self.barcode = barcode
        self.price = price
        self.quantity = quantity
        self.reorderLevel = reorderLevel
        self.locationId = locationId
        self.locationName = locationName
        self.categoryName = categoryName
        self.itemDescription = itemDescription
        self.updatedAt = updatedAt
    }

    var status: InventoryStockStatus {
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
}

enum InventoryStockStatus: String, CaseIterable, Hashable {
    case inStock = "In Stock"
    case lowStock = "Low Stock"
    case outOfStock = "Out of Stock"
    case negative = "Negative"
}
