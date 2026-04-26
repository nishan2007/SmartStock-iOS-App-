//
//  CheckoutService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/26/26.
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
    let payment_reference: String?
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

// MARK: - Private DTOs (used only in this service)

private struct CustomerBalanceRow: Decodable {
    let customer_id: Int
    let current_balance: Double?
    let credit_limit: Double?
    let is_active: Bool?
}

private struct CustomerBalanceUpdate: Encodable {
    let current_balance: Double
}

// MARK: - Enums

enum CheckoutPaymentMethod: String, CaseIterable, Identifiable, Hashable {
    case cash = "CASH"
    case card = "CARD"
    case cheque = "CHEQUE"
    case account = "ACCOUNT"

    var id: String { rawValue }
}

enum CheckoutError: LocalizedError, Identifiable {
    case missingCustomerAccount
    case missingPaymentReference(String)
    case inactiveCustomerAccount
    case creditLimitExceeded
    
    // MARK: - Identifiable
    var id: String {
        switch self {
        case .missingCustomerAccount: return "missingCustomerAccount"
        case .missingPaymentReference: return "missingPaymentReference"
        case .inactiveCustomerAccount: return "inactiveCustomerAccount"
        case .creditLimitExceeded: return "creditLimitExceeded"
        }
    }
    
    var errorDescription: String? {
        switch self {
        case .missingCustomerAccount:
            return "Select a customer account for account billing."
        case .missingPaymentReference(let label):
            return "Enter the \(label)."
        case .inactiveCustomerAccount:
            return "This customer account is inactive."
        case .creditLimitExceeded:
            return "This sale exceeds the customer's available credit."
        }
    }
}

// MARK: - Service

enum CheckoutService {
    
    static func checkout(
        cart: [CartItem],
        user: AppUser,
        store: Store,
        paymentMethod: CheckoutPaymentMethod,
        customerAccountId: Int? = nil,
        paymentReference: String? = nil
    ) async throws {
        
        guard !cart.isEmpty else { return }
        
        let subtotalAmount = cart.reduce(0) { $0 + $1.subtotal }
        let totalDiscountAmount = cart.reduce(0) { $0 + $1.discountAmount }
        let total = max(subtotalAmount - totalDiscountAmount, 0)
        
        let receipt = await MainActor.run {
            ReceiptNumberManager.shared.nextReceipt(for: store.id)
        }
        
        let trimmedReference = paymentReference?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedCustomerAccountId: Int?
        let paymentStatus: String
        let amountPaid: Double
        let resolvedPaymentReference: String?
        
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
            resolvedPaymentReference = nil
            
        case .cash, .card, .cheque:
            if paymentMethod == .card && (trimmedReference?.isEmpty != false) {
                throw CheckoutError.missingPaymentReference("card transaction ID")
            }
            if paymentMethod == .cheque && (trimmedReference?.isEmpty != false) {
                throw CheckoutError.missingPaymentReference("cheque number")
            }
            
            resolvedCustomerAccountId = customerAccountId
            paymentStatus = "PAID"
            amountPaid = total
            resolvedPaymentReference = (paymentMethod == .cash) ? nil : trimmedReference
        }
        
        // Create Sale
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
            payment_reference: resolvedPaymentReference,
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
        
        // Customer Account Transaction (if applicable)
        if let customerId = resolvedCustomerAccountId {
            let transactionType = paymentMethod == .account ? "SALE_CREDIT" : "SALE_PAID"
            let note: String = {
                if paymentMethod == .account {
                    return "sale_id=\(insertedSale.sale_id); billed_to_account"
                } else if let ref = resolvedPaymentReference {
                    return "sale_id=\(insertedSale.sale_id); payment_method=\(paymentMethod.rawValue); payment_reference=\(ref)"
                } else {
                    return "sale_id=\(insertedSale.sale_id); payment_method=\(paymentMethod.rawValue)"
                }
            }()
            
            try await supabase
                .from("customer_account_transactions")
                .insert(NewCustomerAccountTransaction(
                    customer_id: customerId,
                    location_id: store.id,
                    sale_id: insertedSale.sale_id,
                    amount: total,
                    transaction_type: transactionType,
                    note: note,
                    user_name: user.fullName
                ))
                .execute()
        }
        
        // Insert Sale Items
        let saleItems = cart.map { item in
            NewSaleItem(
                sale_id: insertedSale.sale_id,
                product_id: item.product.id,
                quantity: item.quantity,
                unit_price: item.unitPrice
            )
        }
        
        try await supabase.from("sale_items").insert(saleItems).execute()
        
        // Update Inventory for each item
        for item in cart {
            let inventory: InventoryRow = try await supabase
                .from("inventory")
                .select("inventory_id, quantity_on_hand")
                .eq("product_id", value: item.product.id)
                .eq("location_id", value: store.id)
                .single()
                .execute()
                .value
            
            let newQty = inventory.quantity_on_hand - item.quantity
            
            try await supabase
                .from("inventory")
                .update(InventoryQuantityUpdate(quantity_on_hand: newQty))
                .eq("inventory_id", value: inventory.inventory_id)
                .execute()
            
            try await supabase
                .from("inventory_movements")
                .insert(NewInventoryMovement(
                    product_id: item.product.id,
                    location_id: store.id,
                    change_qty: -item.quantity,
                    reason: "SALE",
                    note: "sale_id=\(insertedSale.sale_id)"
                ))
                .execute()
        }
    }
}
