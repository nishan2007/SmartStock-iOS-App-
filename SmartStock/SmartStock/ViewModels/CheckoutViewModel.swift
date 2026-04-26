//
//  CheckoutView.swift
//  SmartStock
//
//  Created by Nishal Narain on 4/26/26.
//

import SwiftUI
import Combine   // ← This is the fix

// MARK: - ViewModel
@MainActor
final class CheckoutViewModel: ObservableObject {
    
    @Published var paymentMethod: CheckoutPaymentMethod = .cash
    @Published var paymentReference: String = ""
    @Published var customerAccountId: Int?
    @Published var isProcessing = false
    @Published var error: CheckoutError?
    @Published var showSuccess = false
    
    let cart: [CartItem]
    let user: AppUser
    let store: Store
    
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
    
    init(cart: [CartItem], user: AppUser, store: Store) {
        self.cart = cart
        self.user = user
        self.store = store
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
            try await CheckoutService.checkout(
                cart: cart,
                user: user,
                store: store,
                paymentMethod: paymentMethod,
                customerAccountId: customerAccountId,
                paymentReference: paymentReference
            )
            
            showSuccess = true
            NotificationCenter.default.post(name: .saleCompleted, object: nil)
            
        } catch let checkoutError as CheckoutError {
            error = checkoutError
        } catch {
            self.error = .missingPaymentReference("Unknown error occurred. Please try again.")
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

// MARK: - Main View
struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CheckoutViewModel
    
    init(cart: [CartItem], user: AppUser, store: Store) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(cart: cart, user: user, store: store))
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        
                        OrderSummaryCard(cart: viewModel.cart, total: viewModel.total)
                        
                        PaymentMethodPicker(selectedPaymentMethod: $viewModel.paymentMethod)
                            .onChange(of: viewModel.paymentMethod) {
                                viewModel.resetDependentFields()
                            }
                        
                        if viewModel.requiresPaymentReference {
                            PaymentReferenceField(
                                text: $viewModel.paymentReference,
                                paymentMethod: viewModel.paymentMethod
                            )
                        }
                        
                        if viewModel.paymentMethod == .account {
                            CustomerAccountPicker(selectedCustomerId: $viewModel.customerAccountId)
                        }
                        
                        Spacer(minLength: 20)
                        
                        Button {
                            Task {
                                await viewModel.completeCheckout()
                            }
                        } label: {
                            Text("Complete Sale • \(viewModel.total.formatted(.currency(code: "USD")))")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.accentColor)
                                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .padding(.horizontal)
                        .disabled(viewModel.isProcessing || !viewModel.isFormValid)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Sale Completed Successfully!", isPresented: $viewModel.showSuccess) {
                Button("Done") { dismiss() }
            } message: {
                Text("Receipt has been generated.")
            }
            .alert(item: $viewModel.error) { error in
                Alert(
                    title: Text("Checkout Failed"),
                    message: Text(error.errorDescription ?? "Please try again."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .overlay {
                if viewModel.isProcessing {
                    ProgressView("Processing Sale...")
                        .padding(40)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(radius: 20)
                }
            }
        }
    }
}

// MARK: - Supporting Views (Liquid Glass Dropdown + Cards)

struct PaymentMethodPicker: View {
    private struct PaymentOption: Identifiable {
        let method: CheckoutPaymentMethod
        let label: String
        let icon: String

        var id: CheckoutPaymentMethod { method }
    }

    @Binding var selectedPaymentMethod: CheckoutPaymentMethod
    
    private let options: [PaymentOption] = [
        PaymentOption(method: .cash, label: "Cash", icon: "dollarsign.circle.fill"),
        PaymentOption(method: .card, label: "Credit / Debit Card", icon: "creditcard.fill"),
        PaymentOption(method: .cheque, label: "Cheque", icon: "doc.text.fill"),
        PaymentOption(method: .account, label: "Customer Account", icon: "person.circle.fill")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Payment Method")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            Menu {
                ForEach(options) { option in
                    Button { selectedPaymentMethod = option.method } label: {
                        Label(option.label, systemImage: option.icon)
                    }
                }
            } label: {
                HStack {
                    Label(currentLabel, systemImage: currentIcon)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.1), radius: 12, y: 6)
            }
        }
        .padding(.horizontal)
    }
    
    private var currentLabel: String { options.first { $0.method == selectedPaymentMethod }?.label ?? "Select Method" }
    private var currentIcon: String { options.first { $0.method == selectedPaymentMethod }?.icon ?? "questionmark.circle" }
}

// (OrderSummaryCard, PaymentReferenceField, CustomerAccountPicker remain the same as before)
struct OrderSummaryCard: View {
    let cart: [CartItem]
    let total: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Order Summary").font(.headline)
            ForEach(cart) { item in
                HStack {
                    Text(item.product.name)
                    Spacer()
                    Text("\(item.quantity) × \(item.unitPrice.formatted(.currency(code: "USD")))")
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("Total").font(.title3.bold())
                Spacer()
                Text(total.formatted(.currency(code: "USD"))).font(.title3.bold())
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal)
    }
}

struct PaymentReferenceField: View {
    @Binding var text: String
    let paymentMethod: CheckoutPaymentMethod
    
    var label: String { paymentMethod == .card ? "Card Transaction ID" : "Cheque Number" }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
        }
        .padding(.horizontal)
    }
}

struct CustomerAccountPicker: View {
    @Binding var selectedCustomerId: Int?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Customer Account").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
            Text("Customer selection coming soon...")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
        }
        .padding(.horizontal)
    }
}

// MARK: - Notification
extension Notification.Name {
    static let saleCompleted = Notification.Name("saleCompleted")
}
