//
//  ReturnsView.swift
//  SmartStock
//

import SwiftUI

struct ReturnsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var receiptNumber = ""
    @State private var barcode = ""
    @State private var quantity = "1"
    @State private var reason = "Customer return"
    @State private var restockItem = true
    @State private var isShowingScanner = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var matchedSaleText: String?
    @State private var matchedItemText: String?

    private let reasons = ["Customer return", "Damaged item", "Wrong item", "Exchange"]

    var body: some View {
        Form {
            OperationStoreSection(storeName: sessionManager.selectedStore?.name)

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

            Section("Return Details") {
                TextField("Receipt or sale number", text: $receiptNumber)
                    .textInputAutocapitalization(.characters)
                HStack {
                    TextField("Scan or enter barcode", text: $barcode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled(true)
                    Button {
                        isShowingScanner = true
                    } label: {
                        Image(systemName: "barcode.viewfinder")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Scan barcode")
                }
                TextField("Quantity", text: $quantity)
                    .keyboardType(.numberPad)
                Picker("Reason", selection: $reason) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason)
                    }
                }
                Toggle("Return item to inventory", isOn: $restockItem)
            }

            if matchedSaleText != nil || matchedItemText != nil {
                Section("Matched Sale") {
                    if let matchedSaleText {
                        Text(matchedSaleText)
                    }

                    if let matchedItemText {
                        Text(matchedItemText)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button(action: submitReturn) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Start Return", systemImage: "arrow.uturn.backward.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)
            }
        }
        .navigationTitle("Returns")
        .sheet(isPresented: $isShowingScanner) {
            BarcodeScannerSheet(
                scannedCode: $barcode,
                isPresented: $isShowingScanner,
                onScanned: { code in
                    barcode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            )
        }
    }

    private func submitReturn() {
        Task {
            await performReturn()
        }
    }

    private func performReturn() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a store first."
            return
        }

        guard let user = sessionManager.currentUser else {
            errorMessage = "No signed in user found."
            return
        }

        guard let quantityValue = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)), quantityValue > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        matchedSaleText = nil
        matchedItemText = nil
        defer { isSubmitting = false }

        do {
            let lookup = try await service.lookupReturnSale(
                query: receiptNumber,
                barcode: barcode,
                storeId: store.id
            )

            matchedSaleText = "Sale #\(lookup.sale.sale_id) • \(lookup.sale.receipt_number ?? "No receipt number")"
            matchedItemText = "\(lookup.item.productName) • Sold qty \(lookup.item.quantity)"

            let result = try await service.createReturn(
                sale: lookup.sale,
                item: lookup.item,
                quantity: quantityValue,
                reason: reason,
                restockItem: restockItem,
                store: store,
                user: user
            )

            successMessage = "Return #\(result.returnId) created for \(result.productName). Refund \(String(format: "$%.2f", result.refundAmount))."
            barcode = ""
            quantity = "1"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
