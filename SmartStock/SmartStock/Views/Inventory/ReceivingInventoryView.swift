//
//  ReceivingInventoryView.swift
//  SmartStock
//

import SwiftUI

struct ReceivingInventoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var barcode = ""
    @State private var shipmentItems: [ReceivingCartItem] = []
    @State private var isShowingScanner = false
    @State private var isSubmitting = false
    @State private var editingQuantityItemID: UUID?
    @State private var editedQuantityText = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receiving Into")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(sessionManager.selectedStore?.name ?? "No store selected")
                        .font(.headline.weight(.semibold))
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if let successMessage {
                    Text(successMessage)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Shipment Item")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Scan barcode or search item", text: $barcode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit {
                                Task {
                                    await addShipmentItem(quantityValue: 1)
                                }
                            }
                        Button {
                            isShowingScanner = true
                        } label: {
                            Image(systemName: "barcode.viewfinder")
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Scan barcode")
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            if shipmentItems.isEmpty {
                ContentUnavailableView(
                    "No Shipment Items",
                    systemImage: "tray",
                    description: Text("Scan products and add them to the shipment before receiving.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(shipmentItems) { item in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.productName)
                                    .font(.headline)

                                Text(item.barcode)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 12)

                            HStack(spacing: 12) {
                                Button {
                                    decreaseQuantity(for: item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    editingQuantityItemID = item.id
                                    editedQuantityText = "\(item.quantity)"
                                } label: {
                                    Text("\(item.quantity)")
                                        .font(.title3.weight(.semibold))
                                        .frame(width: 64, height: 44)
                                        .background(Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    increaseQuantity(for: item)
                                } label: {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete(perform: removeShipmentItems)
                }
                .listStyle(.plain)
            }

            VStack(spacing: 12) {
                HStack {
                    Text("Items")
                    Spacer()
                    Text("\(shipmentItems.count)")
                }
                .font(.subheadline)

                Button("Clear Shipment") {
                    clearShipment()
                }
                .foregroundStyle(.red)
                .disabled(shipmentItems.isEmpty || isSubmitting)

                Button {
                    Task {
                        await submitShipment()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Receive Shipment", systemImage: "tray.and.arrow.down.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(shipmentItems.isEmpty || isSubmitting)
            }
            .padding()
        }
        .navigationTitle("Receiving")
        .sheet(isPresented: $isShowingScanner) {
            BarcodeScannerSheet(
                scannedCode: $barcode,
                isPresented: $isShowingScanner,
                onScanned: { code in
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    barcode = trimmed
                    Task {
                        await addShipmentItem(quantityValue: 1, barcodeOverride: trimmed)
                    }
                }
            )
        }
        .alert("Update Quantity", isPresented: isEditingQuantity) {
            TextField("Quantity", text: $editedQuantityText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                editingQuantityItemID = nil
            }
            Button("Save") {
                applyEditedQuantity()
            }
        } message: {
            Text("Enter the received quantity for this item.")
        }
    }

    private var isEditingQuantity: Binding<Bool> {
        Binding {
            editingQuantityItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingQuantityItemID = nil
            }
        }
    }

    private func addShipmentItem(quantityValue: Int, barcodeOverride: String? = nil) async {
        let trimmedBarcode = (barcodeOverride ?? barcode).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            errorMessage = "Scan or enter a barcode."
            return
        }

        errorMessage = nil
        successMessage = nil

        do {
            guard let product = try await service.searchProduct(trimmedBarcode) else {
                errorMessage = "No product found for that barcode or search."
                return
            }

            if let index = shipmentItems.firstIndex(where: { $0.productId == product.id }) {
                shipmentItems[index].quantity += quantityValue
            } else {
                shipmentItems.append(
                    ReceivingCartItem(
                        productId: product.id,
                        productName: product.name,
                        barcode: trimmedBarcode,
                        quantity: quantityValue
                    )
                )
            }

            barcode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitShipment() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a store first."
            return
        }

        guard let user = sessionManager.currentUser else {
            errorMessage = "No signed in user found."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            let result = try await service.receiveInventory(
                items: shipmentItems.map {
                    ReceiveInventoryItem(
                        productId: $0.productId,
                        productName: $0.productName,
                        quantity: $0.quantity
                    )
                },
                store: store,
                user: user
            )

            successMessage = "\(result.productName) received in batch \(result.receiveId)."
            shipmentItems.removeAll()
            barcode = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeShipmentItems(at offsets: IndexSet) {
        shipmentItems.remove(atOffsets: offsets)
    }

    private func clearShipment() {
        shipmentItems.removeAll()
        errorMessage = nil
        successMessage = nil
        barcode = ""
    }

    private func increaseQuantity(for item: ReceivingCartItem) {
        guard let index = shipmentItems.firstIndex(where: { $0.id == item.id }) else { return }
        shipmentItems[index].quantity += 1
    }

    private func decreaseQuantity(for item: ReceivingCartItem) {
        guard let index = shipmentItems.firstIndex(where: { $0.id == item.id }) else { return }

        if shipmentItems[index].quantity > 1 {
            shipmentItems[index].quantity -= 1
        } else {
            shipmentItems.remove(at: index)
        }
    }

    private func applyEditedQuantity() {
        guard let editingQuantityItemID,
              let index = shipmentItems.firstIndex(where: { $0.id == editingQuantityItemID }) else {
            self.editingQuantityItemID = nil
            return
        }

        guard let quantity = Int(editedQuantityText.trimmingCharacters(in: .whitespacesAndNewlines)),
              quantity > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        shipmentItems[index].quantity = quantity
        self.editingQuantityItemID = nil
    }
}

private struct ReceivingCartItem: Identifiable {
    let id = UUID()
    let productId: Int
    let productName: String
    let barcode: String
    var quantity: Int
}
