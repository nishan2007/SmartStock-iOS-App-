//
//  CheckoutView.swift
//  SmartStock
//

import SwiftUI

// MARK: - Main View
struct CheckoutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: CheckoutViewModel
    
    init(cart: [CartItem], user: AppUser, store: Store, device: TrackedDevice? = nil) {
        _viewModel = StateObject(wrappedValue: CheckoutViewModel(cart: cart, user: user, store: store, device: device))
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
                Button("Print Letter") {
                    Task { await viewModel.printReceipt(format: .letter) }
                }
                Button("Print 40-Col") {
                    Task { await viewModel.printReceipt(format: .fortyColumn) }
                }
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
                    Text(item.product.displayName)
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
