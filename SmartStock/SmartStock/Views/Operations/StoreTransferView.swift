//
//  StoreTransferView.swift
//  SmartStock
//

import SwiftUI

struct StoreTransferView: View {
    private enum TransferPage: String, CaseIterable {
        case send = "Send Transfer"
        case receive = "Receive Transfer"
    }

    @EnvironmentObject private var sessionManager: SessionManager
    private let service = OperationsService()
    @Namespace private var pageSelectorAnimation

    @State private var selectedPage: TransferPage = .send
    @State private var destinationStoreId: Int?
    @State private var barcode = ""
    @State private var notes = ""
    @State private var transferItems: [TransferCartItem] = []
    @State private var isShowingScanner = false
    @State private var isSubmitting = false
    @State private var isLoadingIncoming = false
    @State private var receivingTransferId: Int64?
    @State private var editingTransferItemID: UUID?
    @State private var editedTransferQuantityText = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var incomingTransfers: [IncomingStoreTransfer] = []
    @State private var expandedTransferIds: Set<Int64> = []
    @State private var verifiedQuantities: [Int64: String] = [:]

    private var canAdjustTransferQuantityMismatch: Bool {
        sessionManager.currentUser?.canAccess(.verifyStoreTransferQuantity) == true
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                pageSelector

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedPage == .send ? "Transfer From" : "Receiving Into")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(sessionManager.selectedStore?.name ?? "No store selected")
                        .font(.headline.weight(.semibold))
                }

                if let errorMessage {
                    statusBanner(text: errorMessage, color: .red)
                }

                if let successMessage {
                    statusBanner(text: successMessage, color: .green)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            Group {
                if selectedPage == .send {
                    sendTransferContent
                } else {
                    receiveTransferContent
                }
            }
        }
        .navigationTitle("Store Transfer")
        .task {
            await loadIncomingTransfers()
        }
        .onChange(of: sessionManager.selectedStore?.id) { _, _ in
            Task {
                await loadIncomingTransfers()
            }
        }
        .sheet(isPresented: $isShowingScanner) {
            BarcodeScannerSheet(
                scannedCode: $barcode,
                isPresented: $isShowingScanner,
                onScanned: { code in
                    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    barcode = trimmed
                    Task {
                        await addTransferItem(barcodeOverride: trimmed)
                    }
                }
            )
        }
        .alert("Update Quantity", isPresented: isEditingTransferQuantity) {
            TextField("Quantity", text: $editedTransferQuantityText)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                editingTransferItemID = nil
            }
            Button("Save") {
                applyEditedTransferQuantity()
            }
        } message: {
            Text("Enter the transfer quantity for this item.")
        }
    }

    private var pageSelector: some View {
        HStack(spacing: 6) {
            ForEach(TransferPage.allCases, id: \.self) { page in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedPage = page
                    }
                } label: {
                    Text(page.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selectedPage == page ? Color.primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selectedPage == page {
                                Capsule()
                                    .fill(Color(.secondarySystemBackground))
                                    .matchedGeometryEffect(id: "transfer-page-selector", in: pageSelectorAnimation)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(.tertiarySystemBackground))
        .clipShape(Capsule())
    }

    private var sendTransferContent: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Transfer To")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Destination", selection: $destinationStoreId) {
                        Text("Select store").tag(Int?.none)
                        ForEach(sessionManager.availableStores.filter { $0.id != sessionManager.selectedStore?.id }) { store in
                            Text(store.name).tag(Int?.some(store.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Transfer Item")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Scan barcode or search item", text: $barcode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled(true)
                            .submitLabel(.done)
                            .onSubmit {
                                Task {
                                    await addTransferItem()
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

            if transferItems.isEmpty {
                ContentUnavailableView(
                    "No Transfer Items",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("Scan products and add them to the transfer before sending.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(transferItems) { item in
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
                                    decreaseTransferQuantity(for: item)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.title2)
                                        .frame(width: 40, height: 40)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    editingTransferItemID = item.id
                                    editedTransferQuantityText = "\(item.quantity)"
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
                                    increaseTransferQuantity(for: item)
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
                    .onDelete(perform: removeTransferItems)
                }
                .listStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                HStack {
                    Text("Items")
                    Spacer()
                    Text("\(transferItems.count)")
                }
                .font(.subheadline)

                Button("Clear Transfer") {
                    clearTransferItems()
                }
                .foregroundStyle(.red)
                .disabled(transferItems.isEmpty || isSubmitting)

                Button {
                    Task {
                        await performTransfer()
                    }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Label("Create Transfer", systemImage: "arrow.left.arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(destinationStoreId == nil || transferItems.isEmpty || isSubmitting)
            }
            .padding()
        }
    }

    private var receiveTransferContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Incoming Transfers")
                        .font(.headline)
                    Spacer()
                    if isLoadingIncoming {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Refresh") {
                            Task { await loadIncomingTransfers() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }

                if incomingTransfers.isEmpty {
                    Text(isLoadingIncoming ? "Loading incoming transfers..." : "No incoming transfers.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    ForEach(incomingTransfers) { transfer in
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    if expandedTransferIds.contains(transfer.transferId) {
                                        expandedTransferIds.remove(transfer.transferId)
                                    } else {
                                        expandedTransferIds.insert(transfer.transferId)
                                    }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Transfer #\(transfer.transferId)")
                                            .font(.headline)
                                        Spacer()
                                        Text("\(transfer.totalUnits) unit\(transfer.totalUnits == 1 ? "" : "s")")
                                            .font(.subheadline.weight(.semibold))
                                        Image(systemName: expandedTransferIds.contains(transfer.transferId) ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(transfer.fromStoreName) • \(transfer.itemCount) item\(transfer.itemCount == 1 ? "" : "s")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            if expandedTransferIds.contains(transfer.transferId) {
                                VStack(alignment: .leading, spacing: 10) {
                                    transferMetaRow("From", transfer.fromStoreName)
                                    if let createdAt = transfer.createdAt {
                                        transferMetaRow("Created", createdAt.formatted(date: .abbreviated, time: .shortened))
                                    }
                                    if let userName = transfer.userName, !userName.isEmpty {
                                        transferMetaRow("Sent By", userName)
                                    }
                                    if let note = transfer.note, !note.isEmpty {
                                        transferMetaRow("Note", note)
                                    }

                                    Divider()

                                    ForEach(transfer.items) { item in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(alignment: .top) {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(item.productName)
                                                        .font(.subheadline.weight(.semibold))
                                                    Text(item.sku?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? item.sku! : "Product #\(item.productId)")
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                }
                                                Spacer()
                                                Text("Expected \(item.quantity)")
                                                    .font(.subheadline.weight(.semibold))
                                            }

                                            HStack(alignment: .center, spacing: 12) {
                                                Text("Verified")
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                TextField("Qty", text: bindingForVerifiedQuantity(item))
                                                    .keyboardType(.numberPad)
                                                    .multilineTextAlignment(.trailing)
                                                    .frame(width: 72)
                                                    .textFieldStyle(.roundedBorder)
                                            }

                                            if hasMismatch(for: item) {
                                                Text(canAdjustTransferQuantityMismatch ? "Quantity mismatch will update this transfer to the verified amount." : "This quantity does not match the transfer. A role with Verify Store Transfer Quantity permission is required to receive it with changes.")
                                                    .font(.caption)
                                                    .foregroundStyle(canAdjustTransferQuantityMismatch ? .orange : .red)
                                            }
                                        }
                                    }

                                    Button {
                                        Task {
                                            await receiveTransfer(transfer)
                                        }
                                    } label: {
                                        if receivingTransferId == transfer.transferId {
                                            ProgressView()
                                                .frame(maxWidth: .infinity)
                                        } else {
                                            Label("Receive Transfer", systemImage: "tray.and.arrow.down.fill")
                                                .frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(receivingTransferId != nil || transferHasInvalidVerifiedQuantity(transfer) || transferHasUnauthorizedMismatch(transfer))
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .padding()
        }
        .refreshable {
            await loadIncomingTransfers()
        }
    }

    private func statusBanner(text: String, color: Color) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(color.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var isEditingTransferQuantity: Binding<Bool> {
        Binding {
            editingTransferItemID != nil
        } set: { isPresented in
            if !isPresented {
                editingTransferItemID = nil
            }
        }
    }

    private func addTransferItem(barcodeOverride: String? = nil) async {
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

            if let index = transferItems.firstIndex(where: { $0.productId == product.id }) {
                transferItems[index].quantity += 1
            } else {
                transferItems.append(
                    TransferCartItem(
                        productId: product.id,
                        productName: product.name,
                        barcode: trimmedBarcode,
                        quantity: 1
                    )
                )
            }

            barcode = ""
        } catch {
            errorMessage = error.localizedDescription
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

        guard !transferItems.isEmpty else {
            errorMessage = "Add at least one item to the transfer."
            return
        }

        isSubmitting = true
        errorMessage = nil
        successMessage = nil
        defer { isSubmitting = false }

        do {
            let result = try await service.createStoreTransfer(
                items: transferItems.map {
                    StoreTransferCreateItem(
                        productId: $0.productId,
                        productName: $0.productName,
                        quantity: $0.quantity
                    )
                },
                destinationStoreId: destinationStoreId,
                notes: notes,
                fromStore: store,
                user: user
            )

            successMessage = "Transfer #\(result.transferId) created with \(result.itemCount) item\(result.itemCount == 1 ? "" : "s")."
            clearTransferItems()
            await loadIncomingTransfers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadIncomingTransfers() async {
        guard let store = sessionManager.selectedStore else {
            incomingTransfers = []
            return
        }

        isLoadingIncoming = true
        defer { isLoadingIncoming = false }

        do {
            incomingTransfers = try await service.fetchIncomingStoreTransfers(storeId: store.id)
            syncVerifiedQuantities()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func receiveTransfer(_ transfer: IncomingStoreTransfer) async {
        guard let store = sessionManager.selectedStore else {
            errorMessage = "Select a receiving store first."
            return
        }

        guard let user = sessionManager.currentUser else {
            errorMessage = "No signed in user found."
            return
        }

        receivingTransferId = transfer.transferId
        errorMessage = nil
        successMessage = nil
        defer { receivingTransferId = nil }

        do {
            let result = try await service.receiveStoreTransfer(
                transferId: transfer.transferId,
                receivingStore: store,
                user: user,
                verifiedQuantities: verifiedQuantitiesForTransfer(transfer),
                canAdjustQuantityMismatch: canAdjustTransferQuantityMismatch
            )
            if result.hasAdjustedQuantities {
                successMessage = "Transfer #\(result.transferId) received with verified quantity changes. Receive ID: \(result.receiveId)"
            } else {
                successMessage = "Transfer #\(result.transferId) received successfully. Receive ID: \(result.receiveId)"
            }
            expandedTransferIds.remove(transfer.transferId)
            await loadIncomingTransfers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func transferMetaRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func removeTransferItems(at offsets: IndexSet) {
        transferItems.remove(atOffsets: offsets)
    }

    private func clearTransferItems() {
        transferItems.removeAll()
        barcode = ""
        notes = ""
    }

    private func increaseTransferQuantity(for item: TransferCartItem) {
        guard let index = transferItems.firstIndex(where: { $0.id == item.id }) else { return }
        transferItems[index].quantity += 1
    }

    private func decreaseTransferQuantity(for item: TransferCartItem) {
        guard let index = transferItems.firstIndex(where: { $0.id == item.id }) else { return }

        if transferItems[index].quantity > 1 {
            transferItems[index].quantity -= 1
        } else {
            transferItems.remove(at: index)
        }
    }

    private func applyEditedTransferQuantity() {
        guard let editingTransferItemID,
              let index = transferItems.firstIndex(where: { $0.id == editingTransferItemID }) else {
            self.editingTransferItemID = nil
            return
        }

        guard let quantity = Int(editedTransferQuantityText.trimmingCharacters(in: .whitespacesAndNewlines)),
              quantity > 0 else {
            errorMessage = "Enter a valid quantity."
            return
        }

        transferItems[index].quantity = quantity
        self.editingTransferItemID = nil
    }

    private func bindingForVerifiedQuantity(_ item: IncomingStoreTransferItem) -> Binding<String> {
        Binding(
            get: { verifiedQuantities[item.transferItemId] ?? String(item.quantity) },
            set: { verifiedQuantities[item.transferItemId] = $0 }
        )
    }

    private func syncVerifiedQuantities() {
        let validIds = Set(incomingTransfers.flatMap(\.items).map(\.transferItemId))
        verifiedQuantities = verifiedQuantities.filter { validIds.contains($0.key) }

        for item in incomingTransfers.flatMap(\.items) {
            if verifiedQuantities[item.transferItemId] == nil {
                verifiedQuantities[item.transferItemId] = String(item.quantity)
            }
        }
    }

    private func verifiedQuantitiesForTransfer(_ transfer: IncomingStoreTransfer) -> [Int64: Int] {
        Dictionary(
            uniqueKeysWithValues: transfer.items.map { item in
                let parsed = Int((verifiedQuantities[item.transferItemId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) ?? item.quantity
                return (item.transferItemId, parsed)
            }
        )
    }

    private func hasMismatch(for item: IncomingStoreTransferItem) -> Bool {
        guard let parsed = Int((verifiedQuantities[item.transferItemId] ?? String(item.quantity)).trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        return parsed != item.quantity
    }

    private func transferHasUnauthorizedMismatch(_ transfer: IncomingStoreTransfer) -> Bool {
        !canAdjustTransferQuantityMismatch && transfer.items.contains(where: hasMismatch(for:))
    }

    private func transferHasInvalidVerifiedQuantity(_ transfer: IncomingStoreTransfer) -> Bool {
        transfer.items.contains { item in
            guard let parsed = Int((verifiedQuantities[item.transferItemId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return true
            }
            return parsed <= 0
        }
    }
}

private struct TransferCartItem: Identifiable {
    let id = UUID()
    let productId: Int
    let productName: String
    let barcode: String
    var quantity: Int
}
