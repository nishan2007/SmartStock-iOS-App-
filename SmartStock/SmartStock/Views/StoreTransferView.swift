//
//  StoreTransferView.swift
//  SmartStock
//

import SwiftUI

struct StoreTransferView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var destinationStoreId: Int?
    @State private var barcode = ""
    @State private var quantity = "1"
    @State private var notes = ""
    @State private var isShowingScanner = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var matchedProductName: String?

    var body: some View {
        Form {
            OperationStoreSection(title: "From", storeName: sessionManager.selectedStore?.name)

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

            Section("To") {
                Picker("Destination", selection: $destinationStoreId) {
                    Text("Select store").tag(Int?.none)
                    ForEach(sessionManager.availableStores.filter { $0.id != sessionManager.selectedStore?.id }) { store in
                        Text(store.name).tag(Int?.some(store.id))
                    }
                }
            }

            Section("Items") {
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
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)

                if let matchedProductName {
                    Text(matchedProductName)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(action: submitTransfer) {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Create Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationStoreId == nil || isSubmitting)
            }
        }
        .navigationTitle("Store Transfer")
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

    private func submitTransfer() {
        Task {
            await performTransfer()
        }
    }

    private func performTransfer() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a source store first."
            return
        }

        guard let user = sessionManager.currentUser else {
            errorMessage = "No signed in user found."
            return
        }

        guard let destinationStoreId, destinationStoreId != store.id else {
            errorMessage = "Select a destination store."
            return
        }

        guard let quantityValue = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)), quantityValue > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        matchedProductName = nil
        defer { isSubmitting = false }

        do {
            let product = try await service.fetchProduct(forBarcode: barcode)
            matchedProductName = product?.name

            let result = try await service.createStoreTransfer(
                barcode: barcode,
                quantity: quantityValue,
                destinationStoreId: destinationStoreId,
                notes: notes,
                fromStore: store,
                user: user
            )

            successMessage = "Transfer #\(result.transferId) created for \(result.productName)."
            barcode = ""
            quantity = "1"
            notes = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
