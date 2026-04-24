//
//  InventoryEditorService.swift
//  SmartStock
//

import Foundation
import PostgREST
import Supabase
import UIKit

struct InventoryEditorService {
    func fetchStores() async throws -> [Store] {
        try await StoreService.shared.fetchStores()
    }

    func fetchDepartments() async throws -> [InventoryLookupOption] {
        try await supabase
            .from("categories")
            .select("category_id, name")
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchVendors() async throws -> [VendorLookupOption] {
        try await supabase
            .from("vendors")
            .select("vendor_id, name")
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchEditableProduct(productId: Int, locationId: Int) async throws -> InventoryItemDraft {
        let rows: [EditableProductDTO] = try await supabase
            .from("products")
            .select(
                """
                product_id,
                name,
                sku,
                barcode,
                description,
                cost_price,
                price,
                product_type,
                category_id,
                vendor_id,
                image_url,
                inventory(quantity_on_hand, reorder_level, location_id)
                """
            )
            .eq("product_id", value: productId)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else {
            throw InventoryEditorError.productNotFound
        }

        let additionalBarcodes = try await fetchAdditionalBarcodes(productId: productId)
        var draft = row.toDraft(locationId: locationId)
        draft.additionalBarcodes = additionalBarcodes.joined(separator: "\n")
        return draft
    }

    func save(draft: InventoryItemDraft, selectedImage: UIImage?, user: AppUser?) async throws {
        var draft = draft
        if let selectedImage {
            draft.imageURL = try await ProductImageService.upload(image: selectedImage)
        }

        try validate(draft)

        if let productId = draft.productId {
            try await update(productId: productId, draft: draft, user: user)
        } else {
            try await create(draft: draft, user: user)
        }
    }

    private func create(draft: InventoryItemDraft, user: AppUser?) async throws {
        let product = ProductInsert(
            name: draft.name.trimmed,
            sku: draft.sku.trimmed,
            barcode: draft.barcode.trimmed,
            description: draft.description.trimmed,
            cost_price: try draft.costPrice.decimalValue(fieldName: "Cost price"),
            price: try draft.price.decimalValue(fieldName: "Price"),
            product_type: draft.productType.rawValue,
            category_id: draft.categoryId,
            vendor_id: draft.vendorId,
            image_url: draft.imageURL.trimmed.nilIfEmpty,
            created_by_user_id: user?.id,
            created_by_name: user?.fullName
        )

        let inserted: InsertedProduct = try await supabase
            .from("products")
            .insert(product)
            .select("product_id")
            .single()
            .execute()
            .value

        if draft.isInventoryItem, let locationId = draft.locationId {
            let quantity = try draft.quantity.intValue(fieldName: "Quantity")
            let reorderLevel = try draft.reorderLevel.intValue(fieldName: "Reorder level")
            try await upsertInventory(
                productId: inserted.product_id,
                locationId: locationId,
                quantity: quantity,
                reorderLevel: reorderLevel
            )

            if quantity != 0 {
                try await insertMovement(
                    productId: inserted.product_id,
                    locationId: locationId,
                    changeQty: quantity,
                    reason: "NEW_ITEM",
                    note: "Starting quantity for new item",
                    userName: user?.fullName
                )
            }
        }

        try await replaceBarcodes(productId: inserted.product_id, draft: draft)
    }

    private func update(productId: Int, draft: InventoryItemDraft, user: AppUser?) async throws {
        let update = ProductUpdate(
            name: draft.name.trimmed,
            sku: draft.sku.trimmed,
            barcode: draft.barcode.trimmed,
            description: draft.description.trimmed,
            cost_price: try draft.costPrice.decimalValue(fieldName: "Cost price"),
            price: try draft.price.decimalValue(fieldName: "Price"),
            product_type: draft.productType.rawValue,
            category_id: draft.categoryId,
            vendor_id: draft.vendorId,
            image_url: draft.imageURL.trimmed.nilIfEmpty
        )

        try await supabase
            .from("products")
            .update(update)
            .eq("product_id", value: productId)
            .execute()

        if draft.isInventoryItem, let locationId = draft.locationId {
            let quantity = try draft.quantity.intValue(fieldName: "Quantity")
            let reorderLevel = try draft.reorderLevel.intValue(fieldName: "Reorder level")
            let previousQuantity = try await fetchQuantity(productId: productId, locationId: locationId)

            try await upsertInventory(
                productId: productId,
                locationId: locationId,
                quantity: quantity,
                reorderLevel: reorderLevel
            )

            let change = quantity - previousQuantity
            if change != 0 {
                try await insertMovement(
                    productId: productId,
                    locationId: locationId,
                    changeQty: change,
                    reason: "MANUAL_ADJUSTMENT",
                    note: "Manual adjustment from iOS Edit Item",
                    userName: user?.fullName
                )
            }
        }

        try await replaceBarcodes(productId: productId, draft: draft)
    }

    private func upsertInventory(productId: Int, locationId: Int, quantity: Int, reorderLevel: Int) async throws {
        let payload = InventoryUpsert(
            product_id: productId,
            location_id: locationId,
            quantity_on_hand: quantity,
            reorder_level: reorderLevel
        )

        try await supabase
            .from("inventory")
            .upsert(payload, onConflict: "product_id,location_id")
            .execute()
    }

    private func fetchQuantity(productId: Int, locationId: Int) async throws -> Int {
        let rows: [QuantityDTO] = try await supabase
            .from("inventory")
            .select("quantity_on_hand")
            .eq("product_id", value: productId)
            .eq("location_id", value: locationId)
            .limit(1)
            .execute()
            .value

        return rows.first?.quantity_on_hand ?? 0
    }

    private func insertMovement(
        productId: Int,
        locationId: Int,
        changeQty: Int,
        reason: String,
        note: String,
        userName: String?
    ) async throws {
        let movement = InventoryMovementInsert(
            product_id: productId,
            location_id: locationId,
            change_qty: changeQty,
            reason: reason,
            note: note,
            user_name: userName
        )

        try await supabase
            .from("inventory_movements")
            .insert(movement)
            .execute()
    }

    private func replaceBarcodes(productId: Int, draft: InventoryItemDraft) async throws {
        try await supabase
            .from("product_barcodes")
            .delete()
            .eq("product_id", value: productId)
            .execute()

        let barcodes = normalizedAdditionalBarcodes(from: draft)
        guard !barcodes.isEmpty else { return }

        let inserts = barcodes.map {
            ProductBarcodeInsert(product_id: productId, barcode: $0)
        }

        try await supabase
            .from("product_barcodes")
            .insert(inserts)
            .execute()
    }

    private func fetchAdditionalBarcodes(productId: Int) async throws -> [String] {
        let rows: [ProductBarcodeDTO] = try await supabase
            .from("product_barcodes")
            .select("barcode")
            .eq("product_id", value: productId)
            .order("barcode", ascending: true)
            .execute()
            .value

        return rows.map(\.barcode)
    }

    private func validate(_ draft: InventoryItemDraft) throws {
        guard !draft.name.trimmed.isEmpty,
              !draft.sku.trimmed.isEmpty,
              !draft.barcode.trimmed.isEmpty,
              !draft.costPrice.trimmed.isEmpty,
              !draft.price.trimmed.isEmpty else {
            throw InventoryEditorError.validation("Name, SKU, barcode, cost price, and price are required.")
        }

        _ = try draft.costPrice.decimalValue(fieldName: "Cost price")
        _ = try draft.price.decimalValue(fieldName: "Price")

        if draft.isInventoryItem {
            guard draft.locationId != nil else {
                throw InventoryEditorError.validation("Choose a store for this inventory item.")
            }
            _ = try draft.quantity.intValue(fieldName: "Quantity")
            _ = try draft.reorderLevel.intValue(fieldName: "Reorder level")
        }
    }

    private func normalizedAdditionalBarcodes(from draft: InventoryItemDraft) -> [String] {
        let reserved = Set([draft.sku.trimmed, draft.barcode.trimmed].filter { !$0.isEmpty })
        var seen = Set<String>()

        return draft.additionalBarcodes
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && !reserved.contains($0) }
            .filter { seen.insert($0).inserted }
    }
}

enum InventoryEditorError: LocalizedError {
    case productNotFound
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "The selected product could not be loaded."
        case .validation(let message):
            return message
        }
    }
}

private struct EditableProductDTO: Decodable {
    let product_id: Int
    let name: String
    let sku: String
    let barcode: String?
    let description: String?
    let cost_price: Decimal?
    let price: Decimal
    let product_type: String?
    let category_id: Int?
    let vendor_id: Int?
    let image_url: String?
    let inventory: [EditableInventoryDTO]?

    func toDraft(locationId: Int) -> InventoryItemDraft {
        let locationInventory = inventory?.first { $0.location_id == locationId } ?? inventory?.first
        var draft = InventoryItemDraft()
        draft.productId = product_id
        draft.name = name
        draft.sku = sku
        draft.barcode = barcode ?? ""
        draft.description = description ?? ""
        draft.costPrice = cost_price.map { String(describing: $0) } ?? ""
        draft.price = String(describing: price)
        draft.productType = ProductType.fromDatabaseValue(product_type)
        draft.quantity = "\(locationInventory?.quantity_on_hand ?? 0)"
        draft.reorderLevel = "\(locationInventory?.reorder_level ?? 0)"
        draft.locationId = locationInventory?.location_id ?? locationId
        draft.categoryId = category_id
        draft.vendorId = vendor_id
        draft.imageURL = image_url ?? ""
        return draft
    }
}

private struct EditableInventoryDTO: Decodable {
    let quantity_on_hand: Int
    let reorder_level: Int
    let location_id: Int
}

private struct InsertedProduct: Decodable {
    let product_id: Int
}

private struct QuantityDTO: Decodable {
    let quantity_on_hand: Int
}

private struct ProductBarcodeDTO: Decodable {
    let barcode: String
}

private struct ProductInsert: Encodable {
    let name: String
    let sku: String
    let barcode: String
    let description: String
    let cost_price: Decimal
    let price: Decimal
    let product_type: String
    let category_id: Int?
    let vendor_id: Int?
    let image_url: String?
    let created_by_user_id: Int?
    let created_by_name: String?
}

private struct ProductUpdate: Encodable {
    let name: String
    let sku: String
    let barcode: String
    let description: String
    let cost_price: Decimal
    let price: Decimal
    let product_type: String
    let category_id: Int?
    let vendor_id: Int?
    let image_url: String?
}

private struct InventoryUpsert: Encodable {
    let product_id: Int
    let location_id: Int
    let quantity_on_hand: Int
    let reorder_level: Int
}

private struct ProductBarcodeInsert: Encodable {
    let product_id: Int
    let barcode: String
}

private struct InventoryMovementInsert: Encodable {
    let product_id: Int
    let location_id: Int
    let change_qty: Int
    let reason: String
    let note: String
    let user_name: String?
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func decimalValue(fieldName: String) throws -> Decimal {
        guard let decimal = Decimal(string: trimmed), decimal >= 0 else {
            throw InventoryEditorError.validation("\(fieldName) must be a valid positive number.")
        }
        return decimal
    }

    func intValue(fieldName: String) throws -> Int {
        guard let value = Int(trimmed) else {
            throw InventoryEditorError.validation("\(fieldName) must be a whole number.")
        }
        return value
    }
}
