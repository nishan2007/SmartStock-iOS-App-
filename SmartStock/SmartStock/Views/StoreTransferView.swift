//
//  StoreTransferView.swift
//  SmartStock
//

import SwiftUI

struct StoreTransferView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var destinationStoreId: Int?
    @State private var barcode = ""
    @State private var quantity = "1"
    @State private var notes = ""
    @State private var isShowingScanner = false

    var body: some View {
        Form {
            OperationStoreSection(title: "From", storeName: sessionManager.selectedStore?.name)

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
            }

            Section {
                Button {
                    barcode = ""
                    quantity = "1"
                    notes = ""
                } label: {
                    Label("Create Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationStoreId == nil)
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
}
