//
//  CustomerCustomOrderDetailView.swift
//  SmartStock
//

import SwiftUI

struct CustomerCustomOrderDetailView: View {
    let order: CustomOrder

    @State private var lines: [CustomOrderLine] = []
    @State private var payments: [CustomOrderPayment] = []
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

            Section("Order") {
                detailRow("Order Number", order.displayNumber)
                detailRow("Status", order.status.title)
                detailRow("Payment Status", order.paymentStatus.title)
                detailRow("Total", currency(order.totalAmount))
                detailRow("Paid", currency(order.amountPaid))
                detailRow("Balance", currency(order.balanceDue))

                if let paymentMethod = nonEmpty(order.paymentMethod) {
                    detailRow("Payment Method", displayText(paymentMethod))
                }

                if let dueDate = displayDate(order.dueDate) {
                    detailRow("Due", dueDate)
                }

                if let createdAt = displayDate(order.createdAt) {
                    detailRow("Created", createdAt)
                }
            }

            Section("Lines") {
                if isLoading {
                    loadingRow("Loading lines...")
                } else if lines.isEmpty {
                    ContentUnavailableView(
                        "No Lines",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Custom order line items will appear here.")
                    )
                } else {
                    ForEach(lines) { line in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(line.itemName)
                                        .font(.headline)
                                    if let variantName = nonEmpty(line.variantName) {
                                        Text(variantName)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                Text(line.totalText)
                                    .font(.headline)
                            }

                            lineDetailGrid(line)

                            if let details = nonEmpty(line.customizationDetails) {
                                labeledText("Customization", details)
                            }

                            if let instructions = nonEmpty(line.orderInstructions) {
                                labeledText("Instructions", instructions)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }

            Section("Payments") {
                if isLoading {
                    loadingRow("Loading payments...")
                } else if payments.isEmpty {
                    ContentUnavailableView(
                        "No Payments",
                        systemImage: "banknote",
                        description: Text("Custom order payments will appear here.")
                    )
                } else {
                    ForEach(payments) { payment in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(payment.amountText)
                                    .font(.headline)
                                Spacer()
                                Text(payment.paymentMethod.title)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }

                            if let action = nonEmpty(payment.paymentAction) {
                                detailRow("Action", displayText(action))
                            }

                            if let reference = nonEmpty(payment.paymentReference) {
                                detailRow("Reference", reference)
                            }

                            if let takenBy = nonEmpty(payment.takenByName) {
                                detailRow("Taken By", takenBy)
                            }

                            if let createdAt = displayDate(payment.createdAt) {
                                detailRow("Created", createdAt)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle(order.displayNumber)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    @ViewBuilder
    private func lineDetailGrid(_ line: CustomOrderLine) -> some View {
        VStack(spacing: 4) {
            detailRow("Pricing", line.pricingType.title)
            detailRow("Unit Price", line.priceText)

            if let material = nonEmpty(line.printMaterialName) {
                detailRow("Print Material", material)
            }

            if let size = nonEmpty(line.printSizeName) {
                detailRow("Print Size", size)
            }

            if let charge = line.printCharge {
                detailRow("Print Charge", currency(charge))
            }

            if line.lineDiscountAmount > 0 || line.lineDiscountPercent > 0 {
                detailRow(
                    "Discount",
                    "\(currency(line.lineDiscountAmount)) / \(String(format: "%.2f%%", line.lineDiscountPercent))"
                )
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let fetchedLines = CustomerAccountService.fetchCustomOrderLines(customOrderId: order.customOrderId)
            async let fetchedPayments = CustomerAccountService.fetchCustomOrderPayments(customOrderId: order.customOrderId)

            lines = try await fetchedLines
            payments = try await fetchedPayments
        } catch {
            print("LOAD CUSTOMER CUSTOM ORDER DETAIL ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func labeledText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
    }

    private func loadingRow(_ title: String) -> some View {
        HStack {
            Spacer()
            ProgressView(title)
            Spacer()
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func displayText(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func displayDate(_ value: String?) -> String? {
        guard let date = Sale.parseDate(value) else { return nil }
        return Self.dateFormatter.string(from: date)
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
