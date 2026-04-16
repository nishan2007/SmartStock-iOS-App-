//
//  InventoryService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Supabase

struct InventoryService {
    func fetchInventory(for locationId: Int? = nil) async throws -> [InventoryItem] {
        let rows: [InventoryRowDTO]

        if let locationId {
            rows = try await supabase
                .from("inventory")
                .select(
                    """
                    inventory_id,
                    product_id,
                    location_id,
                    quantity_on_hand,
                    reorder_level,
                    updated_at,
                    product:products!inner(
                        product_id,
                        name,
                        sku,
                        barcode,
                        price,
                        description,
                        category:categories(name)
                    ),
                    location:locations!inner(
                        name
                    )
                    """
                )
                .eq("location_id", value: locationId)
                .order("location_id", ascending: true)
                .order("product_id", ascending: true)
                .execute()
                .value
        } else {
            rows = try await supabase
                .from("inventory")
                .select(
                    """
                    inventory_id,
                    product_id,
                    location_id,
                    quantity_on_hand,
                    reorder_level,
                    updated_at,
                    product:products!inner(
                        product_id,
                        name,
                        sku,
                        barcode,
                        price,
                        description,
                        category:categories(name)
                    ),
                    location:locations!inner(
                        name
                    )
                    """
                )
                .order("location_id", ascending: true)
                .order("product_id", ascending: true)
                .execute()
                .value
        }

        return rows.map { $0.toInventoryItem() }
    }
}

private struct InventoryRowDTO: Decodable {
    let inventory_id: Int
    let product_id: Int
    let location_id: Int
    let quantity_on_hand: Int
    let reorder_level: Int
    let updated_at: String?
    let product: ProductDTO
    let location: LocationDTO

    func toInventoryItem() -> InventoryItem {
        InventoryItem(
            id: "\(product_id)-\(location_id)",
            productId: product.product_id,
            name: product.name,
            sku: product.sku,
            barcode: product.barcode,
            price: product.price,
            quantity: quantity_on_hand,
            reorderLevel: reorder_level,
            locationId: location_id,
            locationName: location.name,
            categoryName: product.category?.name,
            itemDescription: product.description,
            updatedAt: InventoryRowDTO.iso8601Date(from: updated_at)
        )
    }

    private static func iso8601Date(from value: String?) -> Date? {
        guard let value else { return nil }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: value) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct ProductDTO: Decodable {
    let product_id: Int
    let name: String
    let sku: String
    let barcode: String?
    let price: Decimal
    let description: String?
    let category: CategoryDTO?
}

private struct CategoryDTO: Decodable {
    let name: String
}

private struct LocationDTO: Decodable {
    let name: String
}
