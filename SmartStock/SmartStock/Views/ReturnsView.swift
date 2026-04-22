//
//  ReturnsView.swift
//  SmartStock
//

import SwiftUI

struct ReturnsView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var receiptNumber = ""
    @State private var barcode = ""
    @State private var reason = "Customer return"
    @State private var restockItem = true
    @State private var isShowingScanner = false

    private let reasons = ["Customer return", "Damaged item", "Wrong item", "Exchange"]

    var body: some View {
        Form {
            OperationStoreSection(storeName: sessionManager.selectedStore?.name)

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
                Picker("Reason", selection: $reason) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason)
                    }
                }
                Toggle("Return item to inventory", isOn: $restockItem)
            }

            Section {
                Button {
                    receiptNumber = ""
                    barcode = ""
                    restockItem = true
                } label: {
                    Label("Start Return", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
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
}
