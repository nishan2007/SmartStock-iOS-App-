//
//  CheckoutService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation
import Supabase

// MARK: - DTOs

struct NewSale: Encodable {
    let location_id: Int
    let user_id: Int
    let total_amount: Double
    let status: String
    let transaction_source: String
}

struct InsertedSaleRow: Decodable {
    let sale_id: Int
}

struct NewSaleItem: Encodable {
    let sale_id: Int
    let product_id: Int
    let quantity: Int
    let unit_price: Double
}

struct InventoryRow: Decodable {
    let inventory_id: Int
    let quantity_on_hand: Int
}

struct InventoryQuantityUpdate: Encodable {
    let quantity_on_hand: Int
}

struct NewInventoryMovement: Encodable {
    let product_id: Int
    let location_id: Int
    let change_qty: Int
    let reason: String
    let note: String?
}

// MARK: - Service

enum CheckoutService {

    /// Performs a full checkout:
    /// 1) inserts sale header
    /// 2) fetches sale_id
    /// 3) inserts sale_items
    /// 4) updates inventory for the selected store
    /// 5) logs inventory movements
    static func checkout(
        cart: [CartItem],
        user: AppUser,
        store: Store
    ) async throws {

        guard !cart.isEmpty else { return }

        let total = cart.reduce(0) { $0 + $1.lineTotal }

        // 1) Create sale
        let newSale = NewSale(
            location_id: store.id,
            user_id: user.id,
            total_amount: total,
            status: "completed",
            transaction_source: "mobile_app"
        )

        let insertedSale: InsertedSaleRow = try await supabase
            .from("sales")
            .insert(newSale)
            .select("sale_id")
            .single()
            .execute()
            .value

        // 2) Build sale items
        let saleItems = cart.map { item in
            NewSaleItem(
                sale_id: insertedSale.sale_id,
                product_id: item.product.id,
                quantity: item.quantity,
                unit_price: item.product.price ?? 0
            )
        }

        // 3) Insert sale items
        try await supabase
            .from("sale_items")
            .insert(saleItems)
            .execute()

        // 4) Update inventory for each item in the selected store
        for item in cart {
            let inventoryRow: InventoryRow = try await supabase
                .from("inventory")
                .select("inventory_id, quantity_on_hand")
                .eq("product_id", value: item.product.id)
                .eq("location_id", value: store.id)
                .single()
                .execute()
                .value

            let newQuantity = inventoryRow.quantity_on_hand - item.quantity

            try await supabase
                .from("inventory")
                .update(InventoryQuantityUpdate(quantity_on_hand: newQuantity))
                .eq("inventory_id", value: inventoryRow.inventory_id)
                .execute()

            let movement = NewInventoryMovement(
                product_id: item.product.id,
                location_id: store.id,
                change_qty: -item.quantity,
                reason: "sale",
                note: "Sale #\(insertedSale.sale_id)"
            )

            try await supabase
                .from("inventory_movements")
                .insert(movement)
                .execute()
        }
    }
}
