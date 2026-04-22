//
//  ReceivingInventoryView.swift
//  SmartStock
//

import SwiftUI

struct ReceivingInventoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var barcode = ""
    @State private var quantity = "1"
    @State private var cost = ""
    @State private var isShowingScanner = false

    var body: some View {
        Form {
            OperationStoreSection(title: "Receiving Store", storeName: sessionManager.selectedStore?.name)

            Section("Shipment") {
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
                TextField("Quantity received", text: $quantity)
                    .keyboardType(.numberPad)
                TextField("Unit cost", text: $cost)
                    .keyboardType(.decimalPad)
            }

            Section {
                Button {
                    barcode = ""
                    quantity = "1"
                    cost = ""
                } label: {
                    Label("Receive Item", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationTitle("Receiving")
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
