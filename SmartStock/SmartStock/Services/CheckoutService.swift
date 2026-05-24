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
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let device_id: String
    let completed_at: String
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

struct InsertedSaleItemRow: Decodable {
    let sale_item_id: Int
    let sale_id: Int
    let product_id: Int
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
    let user_name: String
    let user_id: Int
    let sale_id: Int
    let sale_item_id: Int
    let device_id: String
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

private struct NewSaleAuditLog: Encodable {
    let sale_id: Int?
    let sale_item_id: Int?
    let return_id: Int64?
    let return_item_id: Int64?
    let customer_id: Int?
    let product_id: Int?
    let location_id: Int
    let action_type: String
    let action_scope: String
    let field_name: String?
    let old_value: String?
    let new_value: String?
    let amount: Double?
    let quantity: Int?
    let reason: String?
    let note: String?
    let user_id: Int
    let user_name: String
    let device_id: String
    let created_at: String
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
        paymentReference: String? = nil,
        device: TrackedDevice? = nil
    ) async throws -> ReceiptPrintPayload? {
        
        guard !cart.isEmpty else { return nil }
        
        let subtotalAmount = cart.reduce(0) { $0 + $1.subtotal }
        let totalDiscountAmount = cart.reduce(0) { $0 + $1.discountAmount }
        let total = max(subtotalAmount - totalDiscountAmount, 0)
        
        let receipt = try await ReceiptNumberManager.shared.nextReceipt(for: store.id)
        let auditTimestamp = ISO8601DateFormatter().string(from: Date())
        let deviceContext = await makeDeviceContext(device: device)
        let cashDrawer: ResolvedCashDrawer?
        if paymentMethod == .cash {
            cashDrawer = try await CashDrawerService().resolveAssignedDrawer(storeId: store.id, deviceId: device?.id)
        } else {
            cashDrawer = nil
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
            transaction_source: "iOS_app",
            receipt_number: receipt.receiptNumber,
            receipt_device_id: receipt.deviceId,
            receipt_sequence: receipt.sequence,
            cash_drawer_id: cashDrawer?.drawerId,
            cash_drawer_name: cashDrawer?.drawerName,
            device_id: deviceContext.id,
            completed_at: auditTimestamp
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
                    payment_method: paymentMethod.rawValue,
                    payment_reference: resolvedPaymentReference,
                    cash_drawer_id: cashDrawer?.drawerId,
                    cash_drawer_name: cashDrawer?.drawerName,
                    note: note,
                    user_name: user.fullName,
                    device_id: deviceContext.id,
                    device_name: deviceContext.name
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
        
        let insertedSaleItems: [InsertedSaleItemRow] = try await supabase
            .from("sale_items")
            .insert(saleItems)
            .select("sale_item_id, sale_id, product_id")
            .execute()
            .value

        var insertedSaleItemByProduct = Dictionary(grouping: insertedSaleItems, by: \.product_id)
        var auditRows: [NewSaleAuditLog] = [
            audit(
                saleId: insertedSale.sale_id,
                customerId: resolvedCustomerAccountId,
                locationId: store.id,
                actionType: "SALE_CREATED",
                actionScope: "SALE",
                amount: total,
                note: "receipt_number=\(receipt.receiptNumber)",
                user: user,
                deviceContext: deviceContext,
                createdAt: auditTimestamp
            ),
            audit(
                saleId: insertedSale.sale_id,
                customerId: resolvedCustomerAccountId,
                locationId: store.id,
                actionType: "PAYMENT_RECORDED",
                actionScope: "SALE",
                fieldName: "payment_method",
                newValue: paymentMethod.rawValue,
                amount: amountPaid,
                note: resolvedPaymentReference.map { "payment_reference=\($0)" },
                user: user,
                deviceContext: deviceContext,
                createdAt: auditTimestamp
            )
        ]

        if paymentMethod == .account {
            auditRows.append(audit(saleId: insertedSale.sale_id, customerId: resolvedCustomerAccountId, locationId: store.id, actionType: "ACCOUNT_CHARGE_RECORDED", actionScope: "SALE", fieldName: "customer_id", newValue: resolvedCustomerAccountId.map(String.init), amount: total, note: "billed_to_account", user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
        }

        if resolvedCustomerAccountId != nil {
            auditRows.append(audit(saleId: insertedSale.sale_id, customerId: resolvedCustomerAccountId, locationId: store.id, actionType: "CUSTOMER_ACCOUNT_TRANSACTION", actionScope: "CUSTOMER_ACCOUNT", fieldName: "transaction_type", newValue: paymentMethod == .account ? "SALE_CREDIT" : "SALE_PAID", amount: total, note: "sale_id=\(insertedSale.sale_id)", user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
        }

        if totalDiscountAmount > 0 {
            auditRows.append(audit(saleId: insertedSale.sale_id, customerId: resolvedCustomerAccountId, locationId: store.id, actionType: "SALE_DISCOUNT_APPLIED", actionScope: "SALE", fieldName: "discount_amount", oldValue: "0", newValue: String(totalDiscountAmount), amount: totalDiscountAmount, user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
        }
        
        // Update Inventory for each item
        for item in cart {
            guard var saleItemRows = insertedSaleItemByProduct[item.product.id],
                  !saleItemRows.isEmpty else {
                continue
            }
            let insertedSaleItem = saleItemRows.removeFirst()
            insertedSaleItemByProduct[item.product.id] = saleItemRows

            auditRows.append(audit(saleId: insertedSale.sale_id, saleItemId: insertedSaleItem.sale_item_id, customerId: resolvedCustomerAccountId, productId: item.product.id, locationId: store.id, actionType: "SALE_ITEM_ADDED", actionScope: "SALE_ITEM", amount: item.lineTotal, quantity: item.quantity, note: item.product.displayName, user: user, deviceContext: deviceContext, createdAt: auditTimestamp))

            let originalPrice = item.product.price ?? 0
            if abs(item.unitPrice - originalPrice) > 0.0001 {
                auditRows.append(audit(saleId: insertedSale.sale_id, saleItemId: insertedSaleItem.sale_item_id, customerId: resolvedCustomerAccountId, productId: item.product.id, locationId: store.id, actionType: "PRICE_OVERRIDE", actionScope: "SALE_ITEM", fieldName: "unit_price", oldValue: String(originalPrice), newValue: String(item.unitPrice), amount: item.unitPrice, quantity: item.quantity, note: item.product.displayName, user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
            }

            if item.discountAmount > 0 {
                auditRows.append(audit(saleId: insertedSale.sale_id, saleItemId: insertedSaleItem.sale_item_id, customerId: resolvedCustomerAccountId, productId: item.product.id, locationId: store.id, actionType: "ITEM_DISCOUNT_APPLIED", actionScope: "SALE_ITEM", fieldName: "discount_amount", oldValue: "0", newValue: String(item.discountAmount), amount: item.discountAmount, quantity: item.quantity, note: item.product.displayName, user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
            }

            let inventoryRows: [InventoryRow] = try await supabase
                .from("inventory")
                .select("inventory_id, quantity_on_hand")
                .eq("product_id", value: item.product.id)
                .eq("location_id", value: store.id)
                .execute()
                .value
            guard let inventory = inventoryRows.first else {
                continue
            }
            
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
                    note: "sale_id=\(insertedSale.sale_id)",
                    user_name: user.fullName,
                    user_id: user.id,
                    sale_id: insertedSale.sale_id,
                    sale_item_id: insertedSaleItem.sale_item_id,
                    device_id: deviceContext.id
                ))
                .execute()

            auditRows.append(audit(saleId: insertedSale.sale_id, saleItemId: insertedSaleItem.sale_item_id, customerId: resolvedCustomerAccountId, productId: item.product.id, locationId: store.id, actionType: "INVENTORY_DEDUCTED", actionScope: "INVENTORY", fieldName: "quantity_on_hand", oldValue: String(inventory.quantity_on_hand), newValue: String(newQty), quantity: -item.quantity, reason: "SALE", note: "sale_id=\(insertedSale.sale_id)", user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
        }

        try await insertAuditRows(auditRows)

        return ReceiptPrintPayload(
            saleId: insertedSale.sale_id,
            receiptNumber: receipt.receiptNumber,
            date: Date(),
            cashierName: user.fullName,
            deviceId: receipt.deviceId,
            customerName: nil,
            storeName: store.name,
            paymentMethod: paymentMethod.rawValue,
            paymentStatus: paymentStatus,
            amountPaid: amountPaid,
            cashCollected: nil,
            changeDue: nil,
            subtotal: subtotalAmount,
            discountAmount: totalDiscountAmount,
            total: total,
            items: cart.map {
                ReceiptPrintLineItem(
                    name: $0.product.displayName,
                    sku: $0.product.sku,
                    quantity: $0.quantity,
                    unitPrice: $0.unitPrice,
                    discountAmount: $0.discountAmount
                )
            }
        )
    }

    private static func insertAuditRows(_ rows: [NewSaleAuditLog]) async throws {
        guard !rows.isEmpty else { return }
        try await supabase.from("sale_audit_log").insert(rows).execute()
    }

    private static func makeDeviceContext(device: TrackedDevice?) async -> (id: String, name: String) {
        let fallbackDeviceName = "UNKNOWN-DEVICE"
        let trimmedDeviceName = device?.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = device?.modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            id: device?.id.uuidString ?? DeviceService.shared.currentInstallationId(),
            name: trimmedDeviceName?.isEmpty == false ? trimmedDeviceName! : (trimmedModelName?.isEmpty == false ? trimmedModelName! : fallbackDeviceName)
        )
    }

    private static func audit(
        saleId: Int?,
        saleItemId: Int? = nil,
        returnId: Int64? = nil,
        returnItemId: Int64? = nil,
        customerId: Int? = nil,
        productId: Int? = nil,
        locationId: Int,
        actionType: String,
        actionScope: String,
        fieldName: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        amount: Double? = nil,
        quantity: Int? = nil,
        reason: String? = nil,
        note: String? = nil,
        user: AppUser,
        deviceContext: (id: String, name: String),
        createdAt: String
    ) -> NewSaleAuditLog {
        NewSaleAuditLog(
            sale_id: saleId,
            sale_item_id: saleItemId,
            return_id: returnId,
            return_item_id: returnItemId,
            customer_id: customerId,
            product_id: productId,
            location_id: locationId,
            action_type: actionType,
            action_scope: actionScope,
            field_name: fieldName,
            old_value: oldValue,
            new_value: newValue,
            amount: amount,
            quantity: quantity,
            reason: reason,
            note: note,
            user_id: user.id,
            user_name: user.fullName,
            device_id: deviceContext.id,
            created_at: createdAt
        )
    }
}
