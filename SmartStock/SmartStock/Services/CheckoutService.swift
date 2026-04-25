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
    let user_name: String
    let subtotal_amount: Double
    let total_amount: Double
    let discount_percent: Double
    let discount_amount: Double
    let status: String
    let payment_method: String
    let customer_id: Int?
    let payment_status: String
    let amount_paid: Double
    let transaction_source: String
    let receipt_number: String
    let receipt_device_id: String
    let receipt_sequence: Int
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

private struct CustomerBalanceRow: Decodable {
    let customer_id: Int
    let current_balance: Double?
    let credit_limit: Double?
    let is_active: Bool?
}

private struct CustomerBalanceUpdate: Encodable {
    let current_balance: Double
}

enum CheckoutPaymentMethod: String {
    case cash = "CASH"
    case card = "CARD"
    case cheque = "CHEQUE"
    case account = "ACCOUNT"
}

enum CheckoutError: LocalizedError {
    case missingCustomerAccount
    case inactiveCustomerAccount
    case creditLimitExceeded

    var errorDescription: String? {
        switch self {
        case .missingCustomerAccount:
            return "Select a customer account for account billing."
        case .inactiveCustomerAccount:
            return "This customer account is inactive."
        case .creditLimitExceeded:
            return "This sale exceeds the customer's available credit."
        }
    }
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
        store: Store,
        paymentMethod: CheckoutPaymentMethod,
        customerAccountId: Int? = nil
    ) async throws {

        guard !cart.isEmpty else { return }

        let itemDiscountAmount = cart.reduce(0) { $0 + $1.discountAmount }
        let subtotalAmount = cart.reduce(0) { $0 + $1.subtotal }
        let totalDiscountAmount = itemDiscountAmount
        let total = max(subtotalAmount - totalDiscountAmount, 0)
        let receipt = await MainActor.run {
            ReceiptNumberManager.shared.nextReceipt(for: store.id)
        }

        let resolvedCustomerAccountId: Int?
        let paymentStatus: String
        let amountPaid: Double

        switch paymentMethod {
        case .account:
            guard let customerAccountId else {
                throw CheckoutError.missingCustomerAccount
            }

            let customer: CustomerBalanceRow = try await supabase
                .from("customer_accounts")
                .select("customer_id, current_balance, credit_limit, is_active")
                .eq("customer_id", value: customerAccountId)
                .single()
                .execute()
                .value

            guard customer.is_active ?? true else {
                throw CheckoutError.inactiveCustomerAccount
            }

            let currentBalance = customer.current_balance ?? 0
            let nextBalance = currentBalance + total
            if let creditLimit = customer.credit_limit, nextBalance > creditLimit {
                throw CheckoutError.creditLimitExceeded
            }

            try await supabase
                .from("customer_accounts")
                .update(CustomerBalanceUpdate(current_balance: nextBalance))
                .eq("customer_id", value: customer.customer_id)
                .execute()

            resolvedCustomerAccountId = customer.customer_id
            paymentStatus = "UNPAID"
            amountPaid = 0
        case .cash, .card, .cheque:
            resolvedCustomerAccountId = customerAccountId
            paymentStatus = "PAID"
            amountPaid = total
        }

        // 1) Create sale
        let newSale = NewSale(
            location_id: store.id,
            user_id: user.id,
            user_name: user.fullName,
            subtotal_amount: subtotalAmount,
            total_amount: total,
            discount_percent: 0,
            discount_amount: totalDiscountAmount,
            status: "COMPLETED",
            payment_method: paymentMethod.rawValue,
            customer_id: resolvedCustomerAccountId,
            payment_status: paymentStatus,
            amount_paid: amountPaid,
            transaction_source: "mobile_app",
            receipt_number: receipt.receiptNumber,
            receipt_device_id: receipt.deviceId,
            receipt_sequence: receipt.sequence
        )

        let insertedSale: InsertedSaleRow = try await supabase
            .from("sales")
            .insert(newSale)
            .select("sale_id")
            .single()
            .execute()
            .value

        if let resolvedCustomerAccountId {
            let transactionType = paymentMethod == .account ? "SALE_CREDIT" : "SALE_PAID"
            let note: String
            if paymentMethod == .account {
                note = "sale_id=\(insertedSale.sale_id); billed_to_account"
            } else {
                note = "sale_id=\(insertedSale.sale_id); payment_method=\(paymentMethod.rawValue)"
            }

            try await supabase
                .from("customer_account_transactions")
                .insert(
                    NewCustomerAccountTransaction(
                        customer_id: resolvedCustomerAccountId,
                        location_id: store.id,
                        sale_id: insertedSale.sale_id,
                        amount: total,
                        transaction_type: transactionType,
                        note: note,
                        user_name: user.fullName
                    )
                )
                .execute()
        }

        // 2) Build sale items
        let saleItems = cart.map { item in
            NewSaleItem(
                sale_id: insertedSale.sale_id,
                product_id: item.product.id,
                quantity: item.quantity,
                unit_price: item.unitPrice
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
                reason: "SALE",
                note: "sale_id=\(insertedSale.sale_id)"
            )

            try await supabase
                .from("inventory_movements")
                .insert(movement)
                .execute()
        }
    }
}
