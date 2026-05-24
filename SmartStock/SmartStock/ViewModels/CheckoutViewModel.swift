//
//  CheckoutView.swift
//  SmartStock
//
//  Created by Nishal Narain on 4/26/26.
//

import SwiftUI
import Combine

// MARK: - ViewModel
@MainActor
final class CheckoutViewModel: ObservableObject {
    
    @Published var paymentMethod: CheckoutPaymentMethod = .cash
    @Published var paymentReference: String = ""
    @Published var customerAccountId: Int?
    @Published var isProcessing = false
    @Published var error: CheckoutError?
    @Published var showSuccess = false
    @Published var receiptPayload: ReceiptPrintPayload?
    
    let cart: [CartItem]
    let user: AppUser
    let store: Store
    let device: TrackedDevice?
    
    var total: Double {
        let subtotal = cart.reduce(0) { $0 + $1.subtotal }
        let discount = cart.reduce(0) { $0 + $1.discountAmount }
        return max(subtotal - discount, 0)
    }
    
    var requiresPaymentReference: Bool {
        paymentMethod == .card || paymentMethod == .cheque
    }
    
    var isFormValid: Bool {
        if requiresPaymentReference && paymentReference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if paymentMethod == .account && customerAccountId ==
            nil {
            return false
        }
        return true
    }
    
    init(cart: [CartItem], user: AppUser, store: Store, device: TrackedDevice? = nil) {
        self.cart = cart
        self.user = user
        self.store = store
        self.device = device
    }
    
    func completeCheckout() async {
        guard isFormValid else {
            if requiresPaymentReference {
                error = .missingPaymentReference(paymentMethod == .card ? "card transaction ID" : "cheque number")
            } else if paymentMethod == .account {
                error = .missingCustomerAccount
            }
            return
        }
        
        isProcessing = true
        error = nil
        defer { isProcessing = false }
        
        do {
            receiptPayload = try await CheckoutService.checkout(
                cart: cart,
                user: user,
                store: store,
                paymentMethod: paymentMethod,
                customerAccountId: customerAccountId,
                paymentReference: paymentReference,
                device: device
            )
            
            showSuccess = true
            NotificationCenter.default.post(name: .saleCompleted, object: nil)
            
        } catch let checkoutError as CheckoutError {
            error = checkoutError
        } catch {
            self.error = .missingPaymentReference("Unknown error occurred. Please try again.")
        }
    }

    func printReceipt(format: ReceiptPrintFormat) async {
        guard let receiptPayload else { return }

        do {
            let preferences = try await CustomOrderService().fetchCompanyPreferences(locationId: store.id)
            ReceiptPrintingService.printReceipt(
                payload: receiptPayload,
                preferences: preferences,
                format: format
            )
        } catch {
            self.error = .missingPaymentReference(error.localizedDescription)
        }
    }
    
    func resetDependentFields() {
        if !requiresPaymentReference {
            paymentReference = ""
        }
        if paymentMethod != .account {
            customerAccountId = nil
        }
    }
}
