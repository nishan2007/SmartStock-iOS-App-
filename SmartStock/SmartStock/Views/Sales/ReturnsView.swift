//
//  ReturnsView.swift
//  SmartStock
//

import SwiftUI

struct ReturnsView: View {
    private enum ScannerTarget: Identifiable {
        case receipt
        case item

        var id: String {
            switch self {
            case .receipt: return "receipt"
            case .item: return "item"
            }
        }
    }

    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()

    @State private var receiptNumber = ""
    @State private var itemBarcode = ""
    @State private var quantity = "1"
    @State private var reason = "Customer return"
    @State private var restockItem = true
    @State private var activeScanner: ScannerTarget?
    @State private var isLoadingReceipt = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var loadedSale: ReturnLookupSale?
    @State private var receiptItems: [ReturnableSaleItem] = []
    @State private var selectedSaleItemId: Int?

    private let reasons = ["Customer return", "Damaged item", "Wrong item", "Exchange"]

    private var selectedItem: ReturnableSaleItem? {
        receiptItems.first(where: { $0.sale_item_id == selectedSaleItemId })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let errorMessage {
                    statusCard(message: errorMessage, color: .red, icon: "exclamationmark.circle.fill")
                }

                if let successMessage {
                    statusCard(message: successMessage, color: .green, icon: "checkmark.circle.fill")
                }

                receiptLookupCard

                if loadedSale != nil {
                    returnWorkflowPanel
                }
            }
            .padding()
        }
        .background(screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Returns")
                    .font(.title2.weight(.semibold))
            }
        }
        .sheet(item: $activeScanner) { target in
            BarcodeScannerSheet(
                scannedCode: binding(for: target),
                isPresented: scannerPresentationBinding(for: target),
                onScanned: { code in
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    switch target {
                    case .receipt:
                        receiptNumber = trimmed
                        Task { await loadReceipt() }
                    case .item:
                        itemBarcode = trimmed
                        Task { await matchItemBarcode() }
                    }
                }
            )
        }
    }

    private var receiptLookupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Receipt Lookup")
                .font(.headline)

            modernField(
                title: "Receipt or Sale Number",
                text: $receiptNumber,
                prompt: "Scan or enter receipt number"
            ) {
                Button {
                    activeScanner = .receipt
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan receipt barcode")
            }

            Button {
                Task { await loadReceipt() }
            } label: {
                if isLoadingReceipt {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label("Load Receipt Items", systemImage: "receipt.text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isLoadingReceipt || receiptNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text("Load the receipt first, then scan an item barcode or pick an item from the receipt history below.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(glassCard)
        .overlay(glassBorder)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var returnWorkflowPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let loadedSale {
                receiptSummarySection(for: loadedSale)
            }

            Divider()

            itemScanSection

            if !receiptItems.isEmpty {
                Divider()
                receiptItemsSection
            }

            if selectedItem != nil {
                Divider()
                returnOptionsSection
                Divider()
                submitSection
            }
        }
        .padding(18)
        .background(glassCard)
        .overlay(glassBorder)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var itemScanSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Receipt Item Search")
                .font(.headline)

            modernField(
                title: "Product Barcode or ID",
                text: $itemBarcode,
                prompt: "Search Product"
            ) {
                Button {
                    activeScanner = .item
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title3.weight(.semibold))
                        .frame(width: 42, height: 42)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan item barcode")
            }
        }
    }

    private func receiptSummarySection(for sale: ReturnLookupSale) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Matched Receipt")
                    .font(.headline)
                Text("Sale #\(sale.sale_id)")
                    .font(.subheadline.weight(.medium))
                Text(sale.receipt_number?.isEmpty == false ? sale.receipt_number! : "No receipt number")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(receiptItems.count) item\(receiptItems.count == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.22))
                .clipShape(Capsule())
        }
    }

    private var receiptItemsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Receipt History")
                .font(.headline)

            VStack(spacing: 10) {
                ForEach(receiptItems, id: \.sale_item_id) { item in
                    receiptItemRow(item)
                }
            }
        }
    }

    private func receiptItemRow(_ item: ReturnableSaleItem) -> some View {
        Button {
            selectedSaleItemId = item.sale_item_id
            errorMessage = nil
        } label: {
            HStack(spacing: 14) {
                receiptItemImage(for: item)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.productName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("ID: \(item.product_id)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(item.quantitySummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(item.unitPriceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: selectedSaleItemId == item.sale_item_id ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedSaleItemId == item.sale_item_id ? Color.accentColor : .secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selectedSaleItemId == item.sale_item_id ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.16))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selectedSaleItemId == item.sale_item_id ? Color.accentColor.opacity(0.65) : Color.black.opacity(0.18), lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var returnOptionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Return Options")
                .font(.headline)

            modernField(title: "Quantity", text: $quantity, prompt: "Quantity to return")
                .keyboardType(.numberPad)

            VStack(alignment: .leading, spacing: 10) {
                Text("Reason")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Reason", selection: $reason) {
                    ForEach(reasons, id: \.self) { reason in
                        Text(reason).tag(reason)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.16), lineWidth: 1.2)
                )
            }

            Toggle(isOn: $restockItem) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Return item to inventory")
                    Text("Keeps stock on hand accurate after the refund.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var submitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: submitReturn) {
                if isSubmitting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                } else {
                    Label("Process Return", systemImage: "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || selectedItem == nil || loadedSale == nil)
        }
    }

    private func statusCard(message: String, color: Color, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(16)
        .background(glassCard)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(color.opacity(0.45), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private func modernField<Trailing: View>(
        title: String,
        text: Binding<String>,
        prompt: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField(prompt, text: text)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)

                trailing()
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(Color.white.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.16), lineWidth: 1.2)
            )
        }
    }

    @ViewBuilder
    private func modernField(title: String, text: Binding<String>, prompt: String) -> some View {
        modernField(title: title, text: text, prompt: prompt) { EmptyView() }
    }

    @ViewBuilder
    private func receiptItemImage(for item: ReturnableSaleItem) -> some View {
        if let imageURL = item.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    receiptItemImagePlaceholder
                }
            }
        } else {
            receiptItemImagePlaceholder
        }
    }

    private var receiptItemImagePlaceholder: some View {
        ZStack {
            Color.white.opacity(0.65)
            Image(systemName: "shippingbox.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var glassCard: some ShapeStyle {
        .ultraThinMaterial
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [.white.opacity(0.45), .black.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.2
            )
    }

    private var screenBackground: some View {
        LinearGradient(
            colors: [Color.orange.opacity(0.10), Color.mint.opacity(0.08), Color(.systemBackground)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private func binding(for target: ScannerTarget) -> Binding<String> {
        switch target {
        case .receipt:
            return $receiptNumber
        case .item:
            return $itemBarcode
        }
    }

    private func scannerPresentationBinding(for target: ScannerTarget) -> Binding<Bool> {
        Binding(
            get: { activeScanner == target },
            set: { isPresented in
                if !isPresented {
                    activeScanner = nil
                }
            }
        )
    }

    private func submitReturn() {
        Task {
            await performReturn()
        }
    }

    private func loadReceipt() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a store first."
            return
        }

        isLoadingReceipt = true
        errorMessage = nil
        successMessage = nil
        loadedSale = nil
        receiptItems = []
        selectedSaleItemId = nil
        defer { isLoadingReceipt = false }

        do {
            let sale = try await service.fetchReturnSale(query: receiptNumber, storeId: store.id)
            let items = try await service.fetchReturnableItems(for: sale.sale_id)

            loadedSale = sale
            receiptItems = items
            if items.count == 1 {
                selectedSaleItemId = items.first?.sale_item_id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func matchItemBarcode() async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a store first."
            return
        }

        guard loadedSale != nil else {
            errorMessage = "Load the receipt before scanning an item barcode."
            return
        }

        let trimmedBarcode = itemBarcode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBarcode.isEmpty else {
            return
        }

        errorMessage = nil

        do {
            let lookup = try await service.lookupReturnSale(
                query: receiptNumber,
                barcode: trimmedBarcode,
                storeId: store.id
            )

            loadedSale = lookup.sale

            if receiptItems.isEmpty || receiptItems.allSatisfy({ $0.sale_id != lookup.sale.sale_id }) {
                receiptItems = try await service.fetchReturnableItems(for: lookup.sale.sale_id)
            }

            selectedSaleItemId = lookup.item.sale_item_id
        } catch {
            errorMessage = error.localizedDescription
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

        guard let loadedSale, let selectedItem else {
            errorMessage = "Load a receipt and select an item to return."
            return
        }

        guard let quantityValue = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)), quantityValue > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        guard quantityValue <= selectedItem.remainingQuantity else {
            errorMessage = "Return quantity cannot exceed the remaining returnable quantity of \(selectedItem.remainingQuantity)."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            let result = try await service.createReturn(
                sale: loadedSale,
                item: selectedItem,
                quantity: quantityValue,
                reason: reason,
                restockItem: restockItem,
                store: store,
                user: user
            )

            successMessage = "Return #\(result.returnId) created for \(result.productName). Refund \(String(format: "$%.2f", result.refundAmount))."
            itemBarcode = ""
            quantity = "1"
            selectedSaleItemId = nil
            receiptItems = try await service.fetchReturnableItems(for: loadedSale.sale_id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ReturnableSaleItem {
    var unitPriceText: String {
        String(format: "$%.2f", unit_price ?? 0)
    }

    var quantitySummaryText: String {
        if returnedQuantity > 0 {
            return "Sold \(quantity) • Returned \(returnedQuantity) • Available \(remainingQuantity)"
        }

        return "Sold qty \(quantity)"
    }
}
