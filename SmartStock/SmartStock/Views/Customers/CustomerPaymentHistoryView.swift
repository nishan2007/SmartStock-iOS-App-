//
//  CustomerPaymentHistoryView.swift
//  SmartStock
//

import SwiftUI

struct CustomerPaymentHistoryView: View {
    let customer: CustomerAccount

    @State private var payments: [CustomerPaymentHistoryEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("Payments", value: "\(payments.count)")
            }

            Section("History") {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Loading payments...")
                        Spacer()
                    }
                } else if payments.isEmpty {
                    ContentUnavailableView(
                        "No Payments Yet",
                        systemImage: "banknote",
                        description: Text("Recorded customer payments will appear here.")
                    )
                } else {
                    ForEach(payments) { payment in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(payment.paymentIdText)
                                        .font(.headline)

                                    if let date = Sale.parseDate(payment.createdAt) {
                                        Text(Self.dateFormatter.string(from: date))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(payment.paymentAmountText)
                                    .font(.headline)
                            }

                            if let userName = nonEmpty(payment.userName) {
                                Text("By \(userName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let note = nonEmpty(payment.note) {
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            if payment.customerAccountPaymentAllocations.isEmpty {
                                Text("No sale allocations")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(payment.customerAccountPaymentAllocations) { allocation in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Sale #\(allocation.saleId)")
                                                .font(.subheadline.weight(.semibold))

                                            if let paymentStatus = nonEmpty(allocation.sales?.paymentStatus) {
                                                Text(paymentStatus.capitalized)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Text(allocation.amountText)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .padding(.vertical, 2)
                                }

                                LabeledContent("Applied", value: String(format: "$%.2f", payment.totalApplied))
                                    .font(.caption.weight(.medium))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Payment History")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadPayments()
        }
        .refreshable {
            await loadPayments()
        }
    }

    private func loadPayments() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            payments = try await CustomerAccountService.fetchPaymentHistory(customerId: customer.customerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
