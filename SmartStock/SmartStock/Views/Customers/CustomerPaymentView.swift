//
//  CustomerPaymentView.swift
//  SmartStock
//

import SwiftUI

struct CustomerPaymentView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager

    let customer: CustomerAccount
    let onPaymentRecorded: (Double) async -> Void

    @State private var displayedBalance: Double
    @State private var paymentAmount = ""
    @State private var note = ""
    @State private var outstandingSales: [CustomerOutstandingSale] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var parsedPaymentAmount: Double? {
        Double(paymentAmount.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var paymentPreview: [(sale: CustomerOutstandingSale, appliedAmount: Double)] {
        var remaining = parsedPaymentAmount ?? 0
        var preview: [(CustomerOutstandingSale, Double)] = []

        for sale in outstandingSales where remaining > 0 {
            let applied = min(remaining, sale.balanceDue)
            guard applied > 0 else { continue }
            preview.append((sale, applied))
            remaining -= applied
        }

        return preview
    }

    private var unappliedAmount: Double {
        max((parsedPaymentAmount ?? 0) - paymentPreview.reduce(0) { $0 + $1.appliedAmount }, 0)
    }

    private var canSave: Bool {
        guard let parsedPaymentAmount else { return false }
        return parsedPaymentAmount > 0 && parsedPaymentAmount <= currentBalance && !isSaving
    }

    init(customer: CustomerAccount, onPaymentRecorded: @escaping (Double) async -> Void) {
        self.customer = customer
        self.onPaymentRecorded = onPaymentRecorded
        _displayedBalance = State(initialValue: customer.currentBalance ?? 0)
    }

    private var currentBalance: Double {
        displayedBalance
    }

    var body: some View {
        List {
            Section("Account Balance") {
                LabeledContent("Current Balance", value: currency(currentBalance))

                if let parsedPaymentAmount, parsedPaymentAmount > 0 {
                    LabeledContent("Balance After Payment", value: currency(max(currentBalance - parsedPaymentAmount, 0)))
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }

            Section("Record Payment") {
                TextField("Payment amount", text: $paymentAmount)
                    .keyboardType(.decimalPad)

                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(2...4)

                Button {
                    Task {
                        await savePayment()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Apply Payment", systemImage: "dollarsign.circle")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(!canSave)
            }

            Section("Allocation Preview") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading open sales...")
                        Spacer()
                    }
                } else if outstandingSales.isEmpty {
                    ContentUnavailableView(
                        "No Open Account Sales",
                        systemImage: "checkmark.circle",
                        description: Text("This customer has no unpaid account-billed sales right now.")
                    )
                } else if paymentPreview.isEmpty {
                    Text("Enter a payment amount to preview how it will be applied oldest-first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(paymentPreview, id: \.sale.id) { preview in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Sale #\(preview.sale.saleId)")
                                    .font(.headline)
                                Spacer()
                                Text(currency(preview.appliedAmount))
                                    .font(.headline)
                            }

                            if let createdAt = preview.sale.createdAt,
                               let date = Sale.parseDate(createdAt) {
                                Text(Self.dateFormatter.string(from: date))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack {
                                Text("Due: \(preview.sale.balanceDueText)")
                                Spacer()
                                Text("Net Sale: \(currency(preview.sale.netTotal))")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }

                    if unappliedAmount > 0 {
                        LabeledContent("Unapplied", value: currency(unappliedAmount))
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .navigationTitle("Customer Payment")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            paymentAmount = String(format: "%.2f", currentBalance)
            await loadOutstandingSales()
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
    }

    private func loadOutstandingSales() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            outstandingSales = try await CustomerAccountService.fetchOutstandingAccountSales(customerId: customer.customerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func savePayment() async {
        guard let user = sessionManager.currentUser else {
            errorMessage = "Sign in again to record payments."
            return
        }

        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a store before recording customer payments."
            return
        }

        guard let parsedPaymentAmount, parsedPaymentAmount > 0 else {
            errorMessage = "Enter a valid payment amount."
            return
        }

        guard parsedPaymentAmount <= currentBalance else {
            errorMessage = "Payment cannot exceed the customer's current balance."
            return
        }

        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            let result = try await CustomerAccountService.recordPayment(
                customerId: customer.customerId,
                amount: parsedPaymentAmount,
                note: note,
                userName: user.fullName,
                locationId: store.id
            )

            successMessage = "Payment recorded as \(result.paymentId)."
            displayedBalance = max(result.newBalance, 0)
            paymentAmount = String(format: "%.2f", displayedBalance)
            note = ""

            await onPaymentRecorded(result.newBalance)
            await loadOutstandingSales()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
