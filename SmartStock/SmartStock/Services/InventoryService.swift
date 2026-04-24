//
//  InventoryService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Supabase

struct InventoryService {
    func productId(forBarcode barcode: String) async throws -> Int? {
        let trimmed = barcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let directMatches: [ProductBarcodeLookupDTO] = try await supabase
            .from("products")
            .select("product_id")
            .or("barcode.eq.\(trimmed),sku.eq.\(trimmed)")
            .limit(1)
            .execute()
            .value

        if let productId = directMatches.first?.product_id {
            return productId
        }

        let extraBarcodeMatches: [ProductBarcodeLookupDTO] = try await supabase
            .from("product_barcodes")
            .select("product_id")
            .eq("barcode", value: trimmed)
            .limit(1)
            .execute()
            .value

        return extraBarcodeMatches.first?.product_id
    }

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
                        cost_price,
                        price,
                        description,
                        created_by_name,
                        product_type,
                        image_url,
                        product_barcodes(barcode),
                        category:categories(name),
                        vendor:vendors(name)
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
                        cost_price,
                        price,
                        description,
                        created_by_name,
                        product_type,
                        image_url,
                        product_barcodes(barcode),
                        category:categories(name),
                        vendor:vendors(name)
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

    func fetchInventoryItem(productId: Int, locationId: Int) async throws -> InventoryItem? {
        let rows: [InventoryRowDTO] = try await supabase
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
                    cost_price,
                    price,
                    description,
                    created_by_name,
                    product_type,
                    image_url,
                    product_barcodes(barcode),
                    category:categories(name),
                    vendor:vendors(name)
                ),
                location:locations!inner(
                    name
                )
                """
            )
            .eq("product_id", value: productId)
            .eq("location_id", value: locationId)
            .limit(1)
            .execute()
            .value

        return rows.first?.toInventoryItem()
    }
}

private struct ProductBarcodeLookupDTO: Decodable {
    let product_id: Int
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
            additionalBarcodes: product.product_barcodes.map(\.barcode),
            price: product.price,
            quantity: quantity_on_hand,
            reorderLevel: reorder_level,
            locationId: location_id,
            locationName: location.name,
            categoryName: product.category?.name,
            vendorName: product.vendor?.name,
            createdByName: product.created_by_name,
            itemDescription: product.description,
            productType: ProductType.fromDatabaseValue(product.product_type),
            costPrice: product.cost_price,
            imageURL: URL(string: product.image_url ?? ""),
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
    let cost_price: Decimal?
    let price: Decimal
    let description: String?
    let created_by_name: String?
    let product_type: String?
    let image_url: String?
    let product_barcodes: [ProductBarcodeDTO]
    let category: CategoryDTO?
    let vendor: VendorDTO?
}

private struct ProductBarcodeDTO: Decodable {
    let barcode: String
}

private struct CategoryDTO: Decodable {
    let name: String
}

private struct VendorDTO: Decodable {
    let name: String
}

private struct LocationDTO: Decodable {
    let name: String
}
