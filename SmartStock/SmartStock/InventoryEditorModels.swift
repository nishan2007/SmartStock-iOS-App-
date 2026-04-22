//
//  InventoryEditorModels.swift
//  SmartStock
//

import Foundation

struct InventoryLookupOption: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "category_id"
        case name
    }
}

struct VendorLookupOption: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id = "vendor_id"
        case name
    }
}

struct InventoryItemDraft {
    var productId: Int?
    var name = ""
    var sku = ""
    var barcode = ""
    var description = ""
    var costPrice = ""
    var price = ""
    var productType: ProductType = .inventory
    var quantity = "0"
    var reorderLevel = "0"
    var locationId: Int?
    var categoryId: Int?
    var vendorId: Int?
    var imageURL = ""
    var additionalBarcodes = ""

    var isInventoryItem: Bool {
        productType == .inventory
    }

    init() {}

    init(item: InventoryItem) {
        productId = item.productId
        name = item.name
        sku = item.sku
        barcode = item.barcode ?? ""
        description = item.itemDescription ?? ""
        costPrice = item.costPrice.map { String(describing: $0) } ?? ""
        price = String(describing: item.price)
        productType = item.productType
        quantity = item.quantityText
        reorderLevel = item.reorderLevelText
        locationId = item.locationId
        imageURL = item.imageURL?.absoluteString ?? ""
    }
}

enum InventoryEditorMode: Hashable {
    case add
    case edit(InventoryItem)

    var title: String {
        switch self {
        case .add:
            return "New Item"
        case .edit:
            return "Edit Item"
        }
    }

    var actionTitle: String {
        switch self {
        case .add:
            return "Save Item"
        case .edit:
            return "Save Changes"
        }
    }
}
