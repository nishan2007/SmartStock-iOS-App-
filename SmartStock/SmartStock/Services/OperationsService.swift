//
//  OperationsService.swift
//  SmartStock
//

import Foundation
import Supabase

struct OperationsService {
    private let client = supabase
    private let inventoryService = InventoryService()
    private let timeClockEntrySelection = "clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out, total_hours_worked, total_earned"

    func fetchProduct(forBarcode barcode: String) async throws -> ScannedProduct? {
        guard let productId = try await inventoryService.productId(forBarcode: barcode) else {
            return nil
        }

        let rows: [ScannedProduct] = try await client
            .from("products")
            .select("product_id, name, size, sku, barcode, product_type")
            .eq("product_id", value: productId)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func searchProduct(_ query: String) async throws -> ScannedProduct? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return nil }

        if let matchedBarcodeProduct = try await fetchProduct(forBarcode: trimmedQuery) {
            return matchedBarcodeProduct
        }

        let rows: [ScannedProduct] = try await client
            .from("products")
            .select("product_id, name, size, sku, barcode, product_type")
            .or("name.ilike.%\(trimmedQuery)%,size.ilike.%\(trimmedQuery)%,sku.ilike.%\(trimmedQuery)%")
            .order("name", ascending: true)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func receiveInventory(
        barcode: String,
        quantity: Int,
        store: Store,
        user: AppUser
    ) async throws -> ReceiveInventoryResult {
        guard let product = try await fetchProduct(forBarcode: barcode) else {
            throw OperationsServiceError.productNotFound
        }

        return try await receiveInventory(
            items: [
                ReceiveInventoryItem(
                    productId: product.id,
                    productName: product.displayName,
                    quantity: quantity
                )
            ],
            store: store,
            user: user
        )
    }

    func receiveInventory(
        items: [ReceiveInventoryItem],
        store: Store,
        user: AppUser
    ) async throws -> ReceiveInventoryResult {
        try await receiveInventory(productItems: items, customItems: [], store: store, user: user)
    }

    func receiveInventory(
        productItems: [ReceiveInventoryItem],
        customItems: [ReceiveCustomOrderItem],
        store: Store,
        user: AppUser
    ) async throws -> ReceiveInventoryResult {
        guard !productItems.isEmpty || !customItems.isEmpty else {
            throw OperationsServiceError.invalidQuantity
        }

        let receiveNumber = try await ReceiptNumberManager.shared.nextReceive(for: store.id)

        let receiveBatch = NewReceivingBatch(
            receive_id: receiveNumber.receiveId,
            location_id: store.id,
            user_id: user.id,
            receive_device_id: receiveNumber.deviceId,
            receive_sequence: receiveNumber.sequence,
            user_name: user.fullName
        )

        _ = try await client
            .from("receiving_batches")
            .insert(receiveBatch)
            .execute()

        for item in productItems {
            let existingInventory = try await fetchInventoryRecord(productId: item.productId, locationId: store.id)
            let newQuantity = (existingInventory?.quantity_on_hand ?? 0) + item.quantity

            if let existingInventory {
                _ = try await client
                    .from("inventory")
                    .update(InventoryQuantityUpdate(quantity_on_hand: newQuantity))
                    .eq("inventory_id", value: existingInventory.inventory_id)
                    .execute()
            } else {
                _ = try await client
                    .from("inventory")
                    .insert(NewInventoryRecord(product_id: item.productId, location_id: store.id, quantity_on_hand: item.quantity))
                    .execute()
            }

            let note = "entered_by_user_id=\(user.id)"
            _ = try await client
                .from("inventory_movements")
                .insert(
                    OperationInventoryMovement(
                        product_id: item.productId,
                        location_id: store.id,
                        change_qty: item.quantity,
                        reason: "INVENTORY_ENTRY",
                        note: note,
                        receive_id: receiveNumber.receiveId,
                        receive_device_id: receiveNumber.deviceId,
                        receive_sequence: receiveNumber.sequence,
                        user_name: user.fullName
                    )
                )
                .execute()
        }

        if !customItems.isEmpty {
            try await CustomOrderService().receiveCustomItems(customItems, receiveNumber: receiveNumber, user: user)
        }

        let summaryName: String
        let totalItemCount = productItems.count + customItems.count
        if totalItemCount == 1, let item = productItems.first {
            summaryName = item.productName
        } else if totalItemCount == 1, let item = customItems.first {
            summaryName = item.itemName
        } else {
            summaryName = "\(totalItemCount) items"
        }

        return ReceiveInventoryResult(productName: summaryName, receiveId: receiveNumber.receiveId)
    }

    func createStoreTransfer(
        barcode: String,
        quantity: Int,
        destinationStoreId: Int,
        notes: String?,
        fromStore: Store,
        user: AppUser
    ) async throws -> StoreTransferResult {
        guard let product = try await fetchProduct(forBarcode: barcode) else {
            throw OperationsServiceError.productNotFound
        }

        return try await createStoreTransfer(
            items: [
                StoreTransferCreateItem(
                    productId: product.id,
                    productName: product.displayName,
                    quantity: quantity
                )
            ],
            destinationStoreId: destinationStoreId,
            notes: notes,
            fromStore: fromStore,
            user: user
        )
    }

    func createStoreTransfer(
        items: [StoreTransferCreateItem],
        destinationStoreId: Int,
        notes: String?,
        fromStore: Store,
        user: AppUser
    ) async throws -> StoreTransferResult {
        guard !items.isEmpty else {
            throw OperationsServiceError.invalidQuantity
        }

        for item in items {
            let sourceInventory = try await fetchInventoryRecord(productId: item.productId, locationId: fromStore.id)
            guard let sourceInventory else {
                throw OperationsServiceError.inventoryNotFound
            }
            guard sourceInventory.quantity_on_hand >= item.quantity else {
                throw OperationsServiceError.insufficientInventory
            }
        }

        let insertedTransfer: InsertedStoreTransfer = try await client
            .from("store_transfers")
            .insert(
                NewStoreTransfer(
                    from_location_id: fromStore.id,
                    to_location_id: destinationStoreId,
                    user_id: user.id,
                    user_name: user.fullName,
                    status: "PENDING",
                    note: normalized(notes)
                )
            )
            .select("transfer_id")
            .single()
            .execute()
            .value

        let transferItems = items.map {
            NewStoreTransferItem(
                transfer_id: insertedTransfer.transfer_id,
                product_id: $0.productId,
                quantity: $0.quantity
            )
        }

        _ = try await client
            .from("store_transfer_items")
            .insert(transferItems)
            .execute()

        for item in items {
            let sourceInventory = try await fetchInventoryRecord(productId: item.productId, locationId: fromStore.id)
            guard let sourceInventory else {
                throw OperationsServiceError.inventoryNotFound
            }

            _ = try await client
                .from("inventory")
                .update(InventoryQuantityUpdate(quantity_on_hand: sourceInventory.quantity_on_hand - item.quantity))
                .eq("inventory_id", value: sourceInventory.inventory_id)
                .execute()

            _ = try await client
                .from("inventory_movements")
                .insert(
                    OperationInventoryMovement(
                        product_id: item.productId,
                        location_id: fromStore.id,
                        change_qty: -item.quantity,
                        reason: "TRANSFER_OUT",
                        note: "transfer_id=\(insertedTransfer.transfer_id); from_location_id=\(fromStore.id); to_location_id=\(destinationStoreId)",
                        receive_id: nil,
                        receive_device_id: nil,
                        receive_sequence: nil,
                        user_name: user.fullName
                    )
                )
                .execute()
        }

        return StoreTransferResult(
            transferId: insertedTransfer.transfer_id,
            itemCount: items.count,
            totalUnits: items.reduce(0) { $0 + $1.quantity }
        )
    }

    func fetchIncomingStoreTransfers(storeId: Int) async throws -> [IncomingStoreTransfer] {
        let transferRows: [IncomingStoreTransferRow] = try await client
            .from("store_transfers")
            .select("transfer_id, from_location_id, to_location_id, user_name, note, created_at, status, from_store:locations!store_transfers_from_location_id_fkey(name)")
            .eq("to_location_id", value: storeId)
            .eq("status", value: "PENDING")
            .order("created_at", ascending: true)
            .execute()
            .value

        var transfers: [IncomingStoreTransfer] = []
        for row in transferRows {
            let itemRows: [IncomingStoreTransferItemRow] = try await client
                .from("store_transfer_items")
                .select("transfer_item_id, product_id, quantity, product:products(name, size, sku)")
                .eq("transfer_id", value: Int(row.transfer_id))
                .order("transfer_item_id", ascending: true)
                .execute()
                .value

            let items = itemRows.map {
                IncomingStoreTransferItem(
                    transferItemId: $0.transfer_item_id,
                    productId: $0.product_id,
                    productName: $0.product?.displayName ?? "Unknown Product",
                    sku: $0.product?.sku,
                    quantity: $0.quantity
                )
            }

            transfers.append(
                IncomingStoreTransfer(
                    transferId: row.transfer_id,
                    fromLocationId: row.from_location_id,
                    toLocationId: row.to_location_id,
                    fromStoreName: row.from_store?.name ?? "Unknown Store",
                    userName: row.user_name,
                    note: row.note,
                    createdAt: row.created_at.flatMap(parseOperationsDate),
                    status: row.status ?? "PENDING",
                    items: items
                )
            )
        }

        return transfers
    }

    func receiveStoreTransfer(
        transferId: Int64,
        receivingStore: Store,
        user: AppUser,
        verifiedQuantities: [Int64: Int] = [:],
        canAdjustQuantityMismatch: Bool = false
    ) async throws -> ReceivedStoreTransferResult {
        let transferRows: [StoreTransferReceiveRow] = try await client
            .from("store_transfers")
            .select("transfer_id, from_location_id, to_location_id, status")
            .eq("transfer_id", value: Int(transferId))
            .limit(1)
            .execute()
            .value

        guard let transfer = transferRows.first else {
            throw OperationsServiceError.transferNotFound
        }

        guard transfer.to_location_id == receivingStore.id else {
            throw OperationsServiceError.transferWrongDestination
        }

        guard transfer.status?.uppercased() == "PENDING" else {
            throw OperationsServiceError.transferAlreadyReceived
        }

        let itemRows: [StoreTransferReceiveItemRow] = try await client
            .from("store_transfer_items")
            .select("transfer_item_id, product_id, quantity")
            .eq("transfer_id", value: Int(transferId))
            .order("transfer_item_id", ascending: true)
            .execute()
            .value

        guard !itemRows.isEmpty else {
            throw OperationsServiceError.transferHasNoItems
        }

        let resolvedItems = try itemRows.map { item -> VerifiedStoreTransferReceiveItem in
            let verifiedQuantity = verifiedQuantities[item.transfer_item_id] ?? item.quantity
            guard verifiedQuantity > 0 else {
                throw OperationsServiceError.invalidQuantity
            }

            return VerifiedStoreTransferReceiveItem(
                transferItemId: item.transfer_item_id,
                productId: item.product_id,
                expectedQuantity: item.quantity,
                receivedQuantity: verifiedQuantity
            )
        }

        let hasQuantityMismatch = resolvedItems.contains { $0.expectedQuantity != $0.receivedQuantity }
        if hasQuantityMismatch && !canAdjustQuantityMismatch {
            throw OperationsServiceError.transferQuantityVerificationPermissionRequired
        }

        let receiveNumber = try await ReceiptNumberManager.shared.nextReceive(for: receivingStore.id)

        let receiveBatch = NewReceivingBatch(
            receive_id: receiveNumber.receiveId,
            location_id: receivingStore.id,
            user_id: user.id,
            receive_device_id: receiveNumber.deviceId,
            receive_sequence: receiveNumber.sequence,
            user_name: user.fullName
        )

        _ = try await client
            .from("receiving_batches")
            .insert(receiveBatch)
            .execute()

        for item in resolvedItems {
            if item.expectedQuantity != item.receivedQuantity {
                let sourceInventory = try await fetchInventoryRecord(productId: item.productId, locationId: transfer.from_location_id)
                let sourceAdjustment = item.expectedQuantity - item.receivedQuantity

                if sourceAdjustment != 0 {
                    if let sourceInventory {
                        let newSourceQuantity = sourceInventory.quantity_on_hand + sourceAdjustment
                        _ = try await client
                            .from("inventory")
                            .update(InventoryQuantityUpdate(quantity_on_hand: newSourceQuantity))
                            .eq("inventory_id", value: sourceInventory.inventory_id)
                            .execute()
                    } else if sourceAdjustment > 0 {
                        _ = try await client
                            .from("inventory")
                            .insert(
                                NewInventoryRecord(
                                    product_id: item.productId,
                                    location_id: transfer.from_location_id,
                                    quantity_on_hand: sourceAdjustment
                                )
                            )
                            .execute()
                    } else {
                        throw OperationsServiceError.inventoryNotFound
                    }

                    _ = try await client
                        .from("inventory_movements")
                        .insert(
                            OperationInventoryMovement(
                                product_id: item.productId,
                                location_id: transfer.from_location_id,
                                change_qty: sourceAdjustment,
                                reason: "TRANSFER_ADJUSTMENT",
                                note: "transfer_id=\(transferId); transfer_item_id=\(item.transferItemId); to_location_id=\(receivingStore.id); expected_quantity=\(item.expectedQuantity); verified_quantity=\(item.receivedQuantity); adjusted_by_user_id=\(user.id)",
                                receive_id: nil,
                                receive_device_id: nil,
                                receive_sequence: nil,
                                user_name: user.fullName
                            )
                        )
                        .execute()
                }

                _ = try await client
                    .from("store_transfer_items")
                    .update(StoreTransferItemQuantityUpdate(quantity: item.receivedQuantity))
                    .eq("transfer_item_id", value: Int(item.transferItemId))
                    .execute()
            }

            let existingInventory = try await fetchInventoryRecord(productId: item.productId, locationId: receivingStore.id)
            let newQuantity = (existingInventory?.quantity_on_hand ?? 0) + item.receivedQuantity

            if let existingInventory {
                _ = try await client
                    .from("inventory")
                    .update(InventoryQuantityUpdate(quantity_on_hand: newQuantity))
                    .eq("inventory_id", value: existingInventory.inventory_id)
                    .execute()
            } else {
                _ = try await client
                    .from("inventory")
                    .insert(NewInventoryRecord(product_id: item.productId, location_id: receivingStore.id, quantity_on_hand: item.receivedQuantity))
                    .execute()
            }

            let note: String
            if item.expectedQuantity == item.receivedQuantity {
                note = "transfer_id=\(transferId); from_location_id=\(transfer.from_location_id); received_by_user_id=\(user.id)"
            } else {
                note = "transfer_id=\(transferId); transfer_item_id=\(item.transferItemId); from_location_id=\(transfer.from_location_id); expected_quantity=\(item.expectedQuantity); received_quantity=\(item.receivedQuantity); received_by_user_id=\(user.id)"
            }

            _ = try await client
                .from("inventory_movements")
                .insert(
                    OperationInventoryMovement(
                        product_id: item.productId,
                        location_id: receivingStore.id,
                        change_qty: item.receivedQuantity,
                        reason: "INVENTORY_ENTRY",
                        note: note,
                        receive_id: receiveNumber.receiveId,
                        receive_device_id: receiveNumber.deviceId,
                        receive_sequence: receiveNumber.sequence,
                        user_name: user.fullName
                    )
                )
                .execute()
        }

        _ = try await client
            .from("store_transfers")
            .update(
                StoreTransferReceiveUpdate(
                    status: "RECEIVED",
                    received_at: ISO8601DateFormatter().string(from: Date()),
                    received_by_user_id: user.id,
                    received_by_name: user.fullName,
                    receive_id: receiveNumber.receiveId
                )
            )
            .eq("transfer_id", value: Int(transferId))
            .execute()

        return ReceivedStoreTransferResult(
            transferId: transferId,
            receiveId: receiveNumber.receiveId,
            itemCount: resolvedItems.count,
            hasAdjustedQuantities: hasQuantityMismatch
        )
    }

    func lookupReturnSale(query: String, barcode: String, storeId: Int) async throws -> ReturnSaleLookupResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OperationsServiceError.missingLookupValue
        }

        let sale = try await fetchSaleForReturn(query: trimmedQuery, storeId: storeId)
        guard let sale else {
            throw OperationsServiceError.saleNotFound
        }

        guard let productId = try await inventoryService.productId(forBarcode: barcode) else {
            throw OperationsServiceError.productNotFound
        }

        let items: [ReturnableSaleItem] = try await client
            .from("sale_items")
            .select("sale_item_id, sale_id, product_id, quantity, unit_price, products(name, size), sale_return_items(quantity)")
            .eq("sale_id", value: sale.sale_id)
            .eq("product_id", value: productId)
            .execute()
            .value

        guard let item = items.first(where: { $0.remainingQuantity > 0 }) else {
            throw OperationsServiceError.saleItemNotFound
        }

        return ReturnSaleLookupResult(sale: sale, item: item)
    }

    func fetchReturnSale(query: String, storeId: Int) async throws -> ReturnLookupSale {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            throw OperationsServiceError.missingLookupValue
        }

        guard let sale = try await fetchSaleForReturn(query: trimmedQuery, storeId: storeId) else {
            throw OperationsServiceError.saleNotFound
        }

        return sale
    }

    func fetchReturnableItems(for saleId: Int) async throws -> [ReturnableSaleItem] {
        try await client
            .from("sale_items")
            .select("sale_item_id, sale_id, product_id, quantity, unit_price, products(name, size, image_url), sale_return_items(quantity)")
            .eq("sale_id", value: saleId)
            .order("sale_item_id", ascending: true)
            .execute()
            .value
    }

    func createReturn(
        sale: ReturnLookupSale,
        item: ReturnableSaleItem,
        quantity: Int,
        reason: String,
        restockItem: Bool,
        store: Store,
        user: AppUser,
        device: TrackedDevice? = nil
    ) async throws -> ReturnResult {
        guard quantity > 0 else {
            throw OperationsServiceError.invalidQuantity
        }
        let alreadyReturnedQuantity = try await returnedQuantity(for: item.sale_item_id)
        let remainingQuantity = max(item.quantity - alreadyReturnedQuantity, 0)

        guard quantity <= remainingQuantity else {
            throw OperationsServiceError.returnQuantityTooHigh
        }

        let refundAmount = Double(quantity) * (item.unit_price ?? 0)
        let auditTimestamp = ISO8601DateFormatter().string(from: Date())
        let deviceContext = await makeDeviceContext(device: device)
        let insertedReturn: InsertedSaleReturn = try await client
            .from("sale_returns")
            .insert(
                NewSaleReturn(
                    sale_id: sale.sale_id,
                    location_id: store.id,
                    user_id: user.id,
                    user_name: user.fullName,
                    refund_method: "CASH",
                    refund_amount: refundAmount,
                    reason: reason,
                    device_id: deviceContext.id,
                    device_name: deviceContext.name
                )
            )
            .select("return_id")
            .single()
            .execute()
            .value

        let insertedReturnItem: InsertedSaleReturnItem = try await client
            .from("sale_return_items")
            .insert(
                NewSaleReturnItem(
                    return_id: insertedReturn.return_id,
                    sale_item_id: item.sale_item_id,
                    product_id: item.product_id,
                    quantity: quantity,
                    unit_price: item.unit_price ?? 0
                )
            )
            .select("return_item_id")
            .single()
            .execute()
            .value

        var auditRows: [OperationSaleAuditLog] = [
            saleAudit(saleId: sale.sale_id, returnId: insertedReturn.return_id, customerId: sale.customer_id, locationId: store.id, actionType: "RETURN_CREATED", actionScope: "RETURN", amount: refundAmount, quantity: quantity, reason: reason, note: "refund_method=CASH", user: user, deviceContext: deviceContext, createdAt: auditTimestamp),
            saleAudit(saleId: sale.sale_id, saleItemId: item.sale_item_id, returnId: insertedReturn.return_id, returnItemId: insertedReturnItem.return_item_id, customerId: sale.customer_id, productId: item.product_id, locationId: store.id, actionType: "RETURN_LINE_RECORDED", actionScope: "RETURN_ITEM", amount: refundAmount, quantity: quantity, reason: reason, note: item.productName, user: user, deviceContext: deviceContext, createdAt: auditTimestamp)
        ]

        _ = try await client
            .from("sales")
            .update(SaleReturnedAmountUpdate(returned_amount: (sale.returned_amount ?? 0) + refundAmount))
            .eq("sale_id", value: sale.sale_id)
            .execute()

        if restockItem, let existingInventory = try await fetchInventoryRecord(productId: item.product_id, locationId: store.id) {
            let newQuantity = existingInventory.quantity_on_hand + quantity

            _ = try await client
                .from("inventory")
                .update(InventoryQuantityUpdate(quantity_on_hand: newQuantity))
                .eq("inventory_id", value: existingInventory.inventory_id)
                .execute()

            _ = try await client
                    .from("inventory_movements")
                    .insert(
                    OperationInventoryMovement(
                        product_id: item.product_id,
                        location_id: store.id,
                        change_qty: quantity,
                        reason: "RETURN",
                        note: "Return #\(insertedReturn.return_id) for sale #\(sale.sale_id)",
                        receive_id: nil,
                        receive_device_id: nil,
                        receive_sequence: nil,
                        user_name: user.fullName,
                        sale_id: sale.sale_id,
                        sale_item_id: item.sale_item_id,
                        sale_return_id: insertedReturn.return_id,
                        device_id: deviceContext.id,
                        device_name: deviceContext.name,
                        user_id: user.id
                    )
                )
                .execute()

            auditRows.append(saleAudit(saleId: sale.sale_id, saleItemId: item.sale_item_id, returnId: insertedReturn.return_id, returnItemId: insertedReturnItem.return_item_id, customerId: sale.customer_id, productId: item.product_id, locationId: store.id, actionType: "RETURN_INVENTORY_RESTOCKED", actionScope: "INVENTORY", fieldName: "quantity_on_hand", oldValue: String(existingInventory.quantity_on_hand), newValue: String(newQuantity), quantity: quantity, reason: "RETURN", note: "return_id=\(insertedReturn.return_id)", user: user, deviceContext: deviceContext, createdAt: auditTimestamp))
        }

        try await insertSaleAuditRows(auditRows)

        return ReturnResult(returnId: insertedReturn.return_id, refundAmount: refundAmount, productName: item.productName)
    }

    private func returnedQuantity(for saleItemId: Int) async throws -> Int {
        let rows: [SaleReturnItemQuantityRow] = try await client
            .from("sale_return_items")
            .select("quantity")
            .eq("sale_item_id", value: saleItemId)
            .execute()
            .value

        return rows.reduce(0) { $0 + $1.quantity }
    }

    func fetchTimeClockEntriesForToday(userId: Int) async throws -> [TimeClockEntry] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }
        
        let formatter = ISO8601DateFormatter()
        
        return try await client
            .from("employee_time_clock")
            .select(timeClockEntrySelection)
            .eq("user_id", value: userId)
            .gte("clock_in", value: formatter.string(from: startOfDay))
            .lt("clock_in", value: formatter.string(from: endOfDay))
            .order("clock_in", ascending: true)
            .execute()
            .value
    }
    
    func fetchOpenTimeClockEntry(userId: Int) async throws -> TimeClockEntry? {
        let rows: [TimeClockEntry] = try await client
            .from("employee_time_clock")
            .select(timeClockEntrySelection)
            .eq("user_id", value: userId)
            .is("clock_out", value: nil)
            .order("clock_in", ascending: false)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func fetchTimeClockHistory(userId: Int) async throws -> [TimeClockEntry] {
        try await client
            .from("employee_time_clock")
            .select(timeClockEntrySelection)
            .eq("user_id", value: userId)
            .order("clock_in", ascending: false)
            .execute()
            .value
    }

    func clockIn(user: AppUser, store: Store?) async throws -> TimeClockEntry {
        let entry: TimeClockEntry = try await client
            .from("employee_time_clock")
            .insert(
                TimeClockInsert(
                    user_id: user.id,
                    user_name: user.fullName,
                    location_id: store?.id,
                    location_name: store?.name
                )
            )
            .select(timeClockEntrySelection)
            .single()
            .execute()
            .value

        return entry
    }

    func clockOut(
        entry: TimeClockEntry,
        compensationProfile: TimeClockCompensationProfile?,
        shouldPayDailyRateForDay: Bool = true
    ) async throws -> TimeClockEntry {
        let clockOutDate = Date()
        let totalHours = entry.roundedWorkedHours(until: clockOutDate)
        let totalEarned = compensationProfile?.earned(
            forSessionHours: totalHours,
            shouldPayDailyRateForDay: shouldPayDailyRateForDay
        )

        let entry: TimeClockEntry = try await client
            .from("employee_time_clock")
            .update(
                TimeClockOutUpdate(
                    clock_out: ISO8601DateFormatter().string(from: clockOutDate),
                    total_hours_worked: totalHours,
                    total_earned: totalEarned
                )
            )
            .eq("clock_id", value: Int(entry.clockId))
            .select(timeClockEntrySelection)
            .single()
            .execute()
            .value

        return entry
    }

    func startLunch(entryId: Int64) async throws -> TimeClockEntry {
        let entry: TimeClockEntry = try await client
            .from("employee_time_clock")
            .update(TimeClockLunchStartUpdate(lunch_start: ISO8601DateFormatter().string(from: Date())))
            .eq("clock_id", value: Int(entryId))
            .select(timeClockEntrySelection)
            .single()
            .execute()
            .value

        return entry
    }

    func endLunch(entryId: Int64) async throws -> TimeClockEntry {
        let entry: TimeClockEntry = try await client
            .from("employee_time_clock")
            .update(TimeClockLunchEndUpdate(lunch_end: ISO8601DateFormatter().string(from: Date())))
            .eq("clock_id", value: Int(entryId))
            .select(timeClockEntrySelection)
            .single()
            .execute()
            .value

        return entry
    }

    func fetchEndOfDayReport(storeId: Int, cashDrawerId: Int64? = nil, for date: Date = Date()) async throws -> EndOfDayReport {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw OperationsServiceError.unexpectedResponse
        }

        let iso = ISO8601DateFormatter()
        let startValue = iso.string(from: startOfDay)
        let endValue = iso.string(from: endOfDay)

        var salesQuery = client
            .from("sales")
            .select("sale_id, receipt_number, created_at, payment_method, payment_status, amount_paid, discount_amount, total_amount, user_name, receipt_device_id, cash_drawer_id, cash_drawer_name")
            .eq("location_id", value: storeId)
            .gte("created_at", value: startValue)
            .lt("created_at", value: endValue)

        if let cashDrawerId {
            salesQuery = salesQuery.eq("cash_drawer_id", value: String(cashDrawerId))
        }

        let sales: [EndOfDaySaleRow] = try await salesQuery
            .order("created_at", ascending: true)
            .execute()
            .value

        let returns: [EndOfDayReturnRow] = try await client
            .from("sale_returns")
            .select("refund_amount")
            .eq("location_id", value: storeId)
            .gte("created_at", value: startValue)
            .lt("created_at", value: endValue)
            .execute()
            .value

        var customerPaymentsQuery = client
            .from("customer_account_transactions")
            .select("transaction_id, payment_id, amount, note, payment_method, payment_reference, cash_drawer_id, cash_drawer_name, created_at, user_name, customer_accounts(name)")
            .eq("transaction_type", value: "PAYMENT")
            .eq("location_id", value: storeId)
            .gte("created_at", value: startValue)
            .lt("created_at", value: endValue)

        if let cashDrawerId {
            customerPaymentsQuery = customerPaymentsQuery.eq("cash_drawer_id", value: String(cashDrawerId))
        }

        let customerPayments: [EndOfDayCustomerPaymentRow] = try await customerPaymentsQuery
            .order("created_at", ascending: true)
            .execute()
            .value

        var totalSales = 0.0
        var discounts = 0.0
        var paid = 0.0
        var cash = 0.0
        var card = 0.0
        var account = 0.0

        for sale in sales {
            let total = sale.total_amount ?? 0
            let amountPaid = sale.amount_paid ?? 0
            let discount = sale.discount_amount ?? 0

            totalSales += total
            discounts += discount
            paid += amountPaid

            switch sale.payment_method?.uppercased() {
            case "CASH":
                cash += amountPaid
            case "CARD", "CHEQUE":
                card += amountPaid
            case "ACCOUNT":
                account += max(total - amountPaid, 0)
            default:
                break
            }
        }

        let customerPaymentCash = customerPayments
            .filter { ($0.payment_method ?? "").uppercased() == "CASH" }
            .reduce(0.0) { $0 + abs($1.amount ?? 0) }
        cash += customerPaymentCash
        paid += customerPaymentCash

        let returnTotal = returns.reduce(0.0) { $0 + ($1.refund_amount ?? 0) }
        let unpaid = max(totalSales - paid, 0)

        return EndOfDayReport(
            transactions: sales.count,
            totalSales: totalSales,
            discounts: discounts,
            returns: returnTotal,
            netSales: totalSales - returnTotal,
            paid: paid,
            unpaid: unpaid,
            cash: cash,
            card: card,
            account: account,
            sales: sales,
            customerPayments: customerPayments
        )
    }

    func fetchTimeClockCompensationProfile(userId: Int) async throws -> TimeClockCompensationProfile? {
        let response = try await client
            .from("users")
            .select("*")
            .eq("user_id", value: userId)
            .limit(1)
            .execute()

        guard
            let objects = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]],
            let row = objects.first
        else {
            return nil
        }

        return TimeClockCompensationProfile(row: row)
    }

    func fetchWorkedHours(userId: Int, from start: Date, to end: Date) async throws -> Double {
        let formatter = ISO8601DateFormatter()
        let rows: [TimeClockEntry] = try await client
            .from("employee_time_clock")
            .select(timeClockEntrySelection)
            .eq("user_id", value: userId)
            .gte("clock_in", value: formatter.string(from: start))
            .lt("clock_in", value: formatter.string(from: end))
            .order("clock_in", ascending: true)
            .execute()
            .value

        return rows.reduce(0) { partial, entry in
            partial + entry.workedHours(until: Date())
        }
    }

    func fetchWorkedDays(userId: Int, from start: Date, to end: Date) async throws -> Int {
        let formatter = ISO8601DateFormatter()
        let rows: [TimeClockEntry] = try await client
            .from("employee_time_clock")
            .select(timeClockEntrySelection)
            .eq("user_id", value: userId)
            .gte("clock_in", value: formatter.string(from: start))
            .lt("clock_in", value: formatter.string(from: end))
            .order("clock_in", ascending: true)
            .execute()
            .value

        let workedDays = rows.reduce(into: Set<Date>()) { result, entry in
            guard entry.workedHours(until: Date()) > 0 else { return }
            result.insert(Calendar.current.startOfDay(for: entry.clockIn))
        }

        return workedDays.count
    }

    private func fetchInventoryRecord(productId: Int, locationId: Int) async throws -> InventoryRecord? {
        let rows: [InventoryRecord] = try await client
            .from("inventory")
            .select("inventory_id, quantity_on_hand")
            .eq("product_id", value: productId)
            .eq("location_id", value: locationId)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    private func fetchSaleForReturn(query: String, storeId: Int) async throws -> ReturnLookupSale? {
        if let saleId = Int(query) {
            let rows: [ReturnLookupSale] = try await client
                .from("sales")
                .select("sale_id, receipt_number, returned_amount, customer_id")
                .eq("sale_id", value: saleId)
                .eq("location_id", value: storeId)
                .limit(1)
                .execute()
                .value
            return rows.first
        }

        let rows: [ReturnLookupSale] = try await client
            .from("sales")
            .select("sale_id, receipt_number, returned_amount, customer_id")
            .eq("receipt_number", value: query)
            .eq("location_id", value: storeId)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    private func insertSaleAuditRows(_ rows: [OperationSaleAuditLog]) async throws {
        guard !rows.isEmpty else { return }
        try await client.from("sale_audit_log").insert(rows).execute()
    }

    private func makeDeviceContext(device: TrackedDevice?) async -> (id: String, name: String) {
        let fallbackDeviceName = "UNKNOWN-DEVICE"
        let trimmedDeviceName = device?.deviceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedModelName = device?.modelName.trimmingCharacters(in: .whitespacesAndNewlines)

        return (
            id: device?.id.uuidString ?? DeviceService.shared.currentInstallationId(),
            name: trimmedDeviceName?.isEmpty == false ? trimmedDeviceName! : (trimmedModelName?.isEmpty == false ? trimmedModelName! : fallbackDeviceName)
        )
    }

    private func saleAudit(
        saleId: Int?,
        saleItemId: Int? = nil,
        returnId: Int64? = nil,
        returnItemId: Int64? = nil,
        customerId: Int? = nil,
        productId: Int? = nil,
        locationId: Int,
        actionType: String,
        actionScope: String,
        fieldName: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil,
        amount: Double? = nil,
        quantity: Int? = nil,
        reason: String? = nil,
        note: String? = nil,
        user: AppUser,
        deviceContext: (id: String, name: String),
        createdAt: String
    ) -> OperationSaleAuditLog {
        OperationSaleAuditLog(
            sale_id: saleId,
            sale_item_id: saleItemId,
            return_id: returnId,
            return_item_id: returnItemId,
            customer_id: customerId,
            product_id: productId,
            location_id: locationId,
            action_type: actionType,
            action_scope: actionScope,
            field_name: fieldName,
            old_value: oldValue,
            new_value: newValue,
            amount: amount,
            quantity: quantity,
            reason: reason,
            note: note,
            user_id: user.id,
            user_name: user.fullName,
            device_id: deviceContext.id,
            device_name: deviceContext.name,
            created_at: createdAt
        )
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseOperationsDate(_ value: String) -> Date? {
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) {
            return date
        }

        let formatterWithFraction = DateFormatter()
        formatterWithFraction.locale = Locale(identifier: "en_US_POSIX")
        formatterWithFraction.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatterWithFraction.date(from: value)
    }
}

enum OperationsServiceError: LocalizedError {
    case missingLookupValue
    case productNotFound
    case saleNotFound
    case saleItemNotFound
    case invalidQuantity
    case returnQuantityTooHigh
    case inventoryNotFound
    case insufficientInventory
    case transferNotFound
    case transferWrongDestination
    case transferAlreadyReceived
    case transferHasNoItems
    case transferQuantityVerificationPermissionRequired
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .missingLookupValue:
            return "Enter a receipt number or sale number."
        case .productNotFound:
            return "No product found for that barcode."
        case .saleNotFound:
            return "No sale found for that receipt or sale number."
        case .saleItemNotFound:
            return "That product was not found on the selected sale."
        case .invalidQuantity:
            return "Enter a valid quantity."
        case .returnQuantityTooHigh:
            return "Return quantity cannot exceed the sold quantity."
        case .inventoryNotFound:
            return "No inventory record found for that item in the selected store."
        case .insufficientInventory:
            return "Not enough quantity on hand for this transfer."
        case .transferNotFound:
            return "Transfer not found."
        case .transferWrongDestination:
            return "This transfer belongs to a different receiving store."
        case .transferAlreadyReceived:
            return "This transfer has already been received."
        case .transferHasNoItems:
            return "This transfer has no items."
        case .transferQuantityVerificationPermissionRequired:
            return "You need permission to change a transfer quantity during receiving."
        case .unexpectedResponse:
            return "The server returned an unexpected response."
        }
    }
}

struct ScannedProduct: Decodable {
    let id: Int
    let name: String
    let size: String?
    let sku: String?
    let barcode: String?
    let productType: String?

    var displayName: String {
        displayProductName(name: name, size: size)
    }

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case name
        case size
        case sku
        case barcode
        case productType = "product_type"
    }
}

struct ReceiveInventoryResult {
    let productName: String
    let receiveId: String
}

struct ReceiveInventoryItem {
    let productId: Int
    let productName: String
    let quantity: Int
}

struct StoreTransferResult {
    let transferId: Int64
    let itemCount: Int
    let totalUnits: Int
}

struct StoreTransferCreateItem {
    let productId: Int
    let productName: String
    let quantity: Int
}

struct ReceivedStoreTransferResult {
    let transferId: Int64
    let receiveId: String
    let itemCount: Int
    let hasAdjustedQuantities: Bool
}

struct IncomingStoreTransfer: Identifiable {
    let transferId: Int64
    let fromLocationId: Int
    let toLocationId: Int
    let fromStoreName: String
    let userName: String?
    let note: String?
    let createdAt: Date?
    let status: String
    let items: [IncomingStoreTransferItem]

    var id: Int64 { transferId }

    var itemCount: Int { items.count }
    var totalUnits: Int { items.reduce(0) { $0 + $1.quantity } }
}

struct IncomingStoreTransferItem: Identifiable {
    let transferItemId: Int64
    let productId: Int
    let productName: String
    let sku: String?
    let quantity: Int

    var id: Int64 { transferItemId }
}

struct ReturnResult {
    let returnId: Int64
    let refundAmount: Double
    let productName: String
}

struct ReturnSaleLookupResult {
    let sale: ReturnLookupSale
    let item: ReturnableSaleItem
}

struct EndOfDayReport {
    let transactions: Int
    let totalSales: Double
    let discounts: Double
    let returns: Double
    let netSales: Double
    let paid: Double
    let unpaid: Double
    let cash: Double
    let card: Double
    let account: Double
    let sales: [EndOfDaySaleRow]
    let customerPayments: [EndOfDayCustomerPaymentRow]
}

struct EndOfDaySaleRow: Decodable, Identifiable {
    let sale_id: Int
    let receipt_number: String?
    let created_at: String?
    let payment_method: String?
    let payment_status: String?
    let amount_paid: Double?
    let discount_amount: Double?
    let total_amount: Double?
    let user_name: String?
    let receipt_device_id: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?

    var id: Int { sale_id }

    var createdAtText: String {
        guard let created_at, let date = Sale.parseDate(created_at) else {
            return "Unavailable"
        }
        return Self.displayFormatter.string(from: date)
    }

    var receiptText: String {
        let trimmed = receipt_number?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No receipt" : trimmed
    }

    var employeeText: String {
        let trimmed = user_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    var deviceText: String {
        let trimmed = receipt_device_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Device" : trimmed
    }

    var drawerText: String {
        let trimmed = cash_drawer_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No drawer" : trimmed
    }

    var amountPaidText: String {
        String(format: "$%.2f", amount_paid ?? 0)
    }

    var totalAmountText: String {
        String(format: "$%.2f", total_amount ?? 0)
    }

    static let displayTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let displayFormatter = displayTimeFormatter
}

private struct EndOfDayReturnRow: Decodable {
    let refund_amount: Double?
}

struct EndOfDayCustomerPaymentAccount: Decodable {
    let name: String?
}

struct EndOfDayCustomerPaymentRow: Decodable, Identifiable {
    let transaction_id: Int
    let payment_id: String?
    let amount: Double?
    let note: String?
    let payment_method: String?
    let payment_reference: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let created_at: String?
    let user_name: String?
    let customer_accounts: EndOfDayCustomerPaymentAccount?

    var id: Int { transaction_id }

    var paymentIdText: String {
        let trimmed = payment_id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String(format: "PAY-%06d", transaction_id) : trimmed
    }

    var customerName: String {
        let trimmed = customer_accounts?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Customer" : trimmed
    }

    var employeeText: String {
        let trimmed = user_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    var paymentMethodText: String {
        let trimmed = payment_method?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Unknown Payment" : trimmed
    }

    var drawerText: String {
        let trimmed = cash_drawer_name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No drawer" : trimmed
    }

    var createdAtText: String {
        guard let created_at, let date = Sale.parseDate(created_at) else {
            return "Unavailable"
        }
        return EndOfDaySaleRow.displayTimeFormatter.string(from: date)
    }

    var amountText: String {
        String(format: "$%.2f", abs(amount ?? 0))
    }
}

private struct InventoryRecord: Decodable {
    let inventory_id: Int
    let quantity_on_hand: Int
}

private struct NewInventoryRecord: Encodable {
    let product_id: Int
    let location_id: Int
    let quantity_on_hand: Int
}

private struct NewReceivingBatch: Encodable {
    let receive_id: String
    let location_id: Int
    let user_id: Int
    let receive_device_id: String
    let receive_sequence: Int
    let user_name: String
}

private struct OperationInventoryMovement: Encodable {
    let product_id: Int
    let location_id: Int
    let change_qty: Int
    let reason: String
    let note: String?
    let receive_id: String?
    let receive_device_id: String?
    let receive_sequence: Int?
    let user_name: String?
    let sale_id: Int?
    let sale_item_id: Int?
    let sale_return_id: Int64?
    let device_id: String?
    let device_name: String?
    let user_id: Int?

    init(
        product_id: Int,
        location_id: Int,
        change_qty: Int,
        reason: String,
        note: String?,
        receive_id: String?,
        receive_device_id: String?,
        receive_sequence: Int?,
        user_name: String?,
        sale_id: Int? = nil,
        sale_item_id: Int? = nil,
        sale_return_id: Int64? = nil,
        device_id: String? = nil,
        device_name: String? = nil,
        user_id: Int? = nil
    ) {
        self.product_id = product_id
        self.location_id = location_id
        self.change_qty = change_qty
        self.reason = reason
        self.note = note
        self.receive_id = receive_id
        self.receive_device_id = receive_device_id
        self.receive_sequence = receive_sequence
        self.user_name = user_name
        self.sale_id = sale_id
        self.sale_item_id = sale_item_id
        self.sale_return_id = sale_return_id
        self.device_id = device_id
        self.device_name = device_name
        self.user_id = user_id
    }
}

private struct OperationSaleAuditLog: Encodable {
    let sale_id: Int?
    let sale_item_id: Int?
    let return_id: Int64?
    let return_item_id: Int64?
    let customer_id: Int?
    let product_id: Int?
    let location_id: Int
    let action_type: String
    let action_scope: String
    let field_name: String?
    let old_value: String?
    let new_value: String?
    let amount: Double?
    let quantity: Int?
    let reason: String?
    let note: String?
    let user_id: Int
    let user_name: String
    let device_id: String
    let device_name: String
    let created_at: String
}

private struct NewStoreTransfer: Encodable {
    let from_location_id: Int
    let to_location_id: Int
    let user_id: Int
    let user_name: String
    let status: String
    let note: String?
}

private struct InsertedStoreTransfer: Decodable {
    let transfer_id: Int64
}

private struct NewStoreTransferItem: Encodable {
    let transfer_id: Int64
    let product_id: Int
    let quantity: Int
}

private struct IncomingStoreTransferRow: Decodable {
    let transfer_id: Int64
    let from_location_id: Int
    let to_location_id: Int
    let user_name: String?
    let note: String?
    let created_at: String?
    let status: String?
    let from_store: TransferLocationName?
}

private struct TransferLocationName: Decodable {
    let name: String?
}

private struct IncomingStoreTransferItemRow: Decodable {
    let transfer_item_id: Int64
    let product_id: Int
    let quantity: Int
    let product: TransferProductSummary?
}

private struct TransferProductSummary: Decodable {
    let name: String?
    let size: String?
    let sku: String?

    var displayName: String {
        displayProductName(name: name ?? "Unknown Product", size: size)
    }
}

private struct StoreTransferReceiveRow: Decodable {
    let transfer_id: Int64
    let from_location_id: Int
    let to_location_id: Int
    let status: String?
}

private struct StoreTransferReceiveItemRow: Decodable {
    let transfer_item_id: Int64
    let product_id: Int
    let quantity: Int
}

private struct VerifiedStoreTransferReceiveItem {
    let transferItemId: Int64
    let productId: Int
    let expectedQuantity: Int
    let receivedQuantity: Int
}

private struct StoreTransferItemQuantityUpdate: Encodable {
    let quantity: Int
}

private struct StoreTransferReceiveUpdate: Encodable {
    let status: String
    let received_at: String
    let received_by_user_id: Int
    let received_by_name: String
    let receive_id: String
}

struct ReturnLookupSale: Decodable {
    let sale_id: Int
    let receipt_number: String?
    let returned_amount: Double?
    let customer_id: Int?
}

struct ReturnableProductSummary: Decodable {
    let name: String?
    let size: String?
    let image_url: String?
}

struct SaleReturnItemQuantityRow: Decodable {
    let quantity: Int
}

struct ReturnableSaleItem: Decodable {
    let sale_item_id: Int
    let sale_id: Int
    let product_id: Int
    let quantity: Int
    let unit_price: Double?
    let products: ReturnableProductSummary?
    let sale_return_items: [SaleReturnItemQuantityRow]?

    var id: Int { sale_item_id }

    var productName: String {
        displayProductName(name: products?.name ?? "Unknown Product", size: products?.size)
    }

    var imageURL: URL? {
        guard let value = products?.image_url?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return URL(string: value)
    }

    var returnedQuantity: Int {
        sale_return_items?.reduce(0) { $0 + $1.quantity } ?? 0
    }

    var remainingQuantity: Int {
        max(quantity - returnedQuantity, 0)
    }
}

private struct NewSaleReturn: Encodable {
    let sale_id: Int
    let location_id: Int
    let user_id: Int
    let user_name: String
    let refund_method: String
    let refund_amount: Double
    let reason: String
    let device_id: String
    let device_name: String
}

private struct InsertedSaleReturn: Decodable {
    let return_id: Int64
}

private struct NewSaleReturnItem: Encodable {
    let return_id: Int64
    let sale_item_id: Int
    let product_id: Int
    let quantity: Int
    let unit_price: Double
}

private struct InsertedSaleReturnItem: Decodable {
    let return_item_id: Int64
}

private struct SaleReturnedAmountUpdate: Encodable {
    let returned_amount: Double
}

struct TimeClockEntry: Decodable {
    let clockId: Int64
    let userId: Int
    let userName: String?
    let locationId: Int?
    let locationName: String?
    let workDate: String?
    let clockIn: Date
    let lunchStart: Date?
    let lunchEnd: Date?
    let clockOut: Date?
    let totalHoursWorked: Double?
    let totalEarned: Double?

    var isOpen: Bool {
        clockOut == nil
    }

    var isOnLunch: Bool {
        lunchStart != nil && lunchEnd == nil && clockOut == nil
    }

    func workedHours(until now: Date = Date()) -> Double {
        if clockOut != nil, let totalHoursWorked {
            return totalHoursWorked
        }

        return calculatedWorkedHours(until: now)
    }

    func roundedWorkedHours(until now: Date = Date()) -> Double {
        (calculatedWorkedHours(until: now) * 100).rounded() / 100
    }

    private func calculatedWorkedHours(until now: Date) -> Double {
        let shiftEnd = clockOut ?? now
        guard shiftEnd > clockIn else { return 0 }

        var worked = shiftEnd.timeIntervalSince(clockIn)

        if let lunchStart {
            let lunchStop = lunchEnd ?? min(now, shiftEnd)
            if lunchStop > lunchStart {
                worked -= lunchStop.timeIntervalSince(lunchStart)
            }
        }

        return max(worked, 0) / 3600
    }

    enum CodingKeys: String, CodingKey {
        case clockId = "clock_id"
        case userId = "user_id"
        case userName = "user_name"
        case locationId = "location_id"
        case locationName = "location_name"
        case workDate = "work_date"
        case clockIn = "clock_in"
        case lunchStart = "lunch_start"
        case lunchEnd = "lunch_end"
        case clockOut = "clock_out"
        case totalHoursWorked = "total_hours_worked"
        case totalEarned = "total_earned"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clockId = try container.decode(Int64.self, forKey: .clockId)
        userId = try container.decode(Int.self, forKey: .userId)
        userName = try container.decodeIfPresent(String.self, forKey: .userName)
        locationId = try container.decodeIfPresent(Int.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        workDate = try container.decodeIfPresent(String.self, forKey: .workDate)
        clockIn = try Self.decodeDate(for: .clockIn, in: container)
        lunchStart = try Self.decodeOptionalDate(for: .lunchStart, in: container)
        lunchEnd = try Self.decodeOptionalDate(for: .lunchEnd, in: container)
        clockOut = try Self.decodeOptionalDate(for: .clockOut, in: container)
        totalHoursWorked = try container.decodeIfPresent(Double.self, forKey: .totalHoursWorked)
        totalEarned = try container.decodeIfPresent(Double.self, forKey: .totalEarned)
    }

    private static func decodeDate(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date {
        let value = try container.decode(String.self, forKey: key)
        guard let parsed = parseDate(value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unsupported date format: \(value)")
        }
        return parsed
    }

    private static func decodeOptionalDate(
        for key: CodingKeys,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return parseDate(value)
    }

    private static func parseDate(_ value: String) -> Date? {
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = formatter.date(from: value) {
            return date
        }

        let formatterWithFraction = DateFormatter()
        formatterWithFraction.locale = Locale(identifier: "en_US_POSIX")
        formatterWithFraction.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        return formatterWithFraction.date(from: value)
    }
}

private struct TimeClockInsert: Encodable {
    let user_id: Int
    let user_name: String
    let location_id: Int?
    let location_name: String?
}

private struct TimeClockOutUpdate: Encodable {
    let clock_out: String
    let total_hours_worked: Double
    let total_earned: Double?
}

private struct TimeClockLunchStartUpdate: Encodable {
    let lunch_start: String
}

private struct TimeClockLunchEndUpdate: Encodable {
    let lunch_end: String
}

struct TimeClockCompensationProfile {
    enum CompensationType: String {
        case salary
        case daily
        case hourly
        case unknown

        var displayName: String {
            switch self {
            case .salary: return "Salary"
            case .daily: return "Daily"
            case .hourly: return "Hourly"
            case .unknown: return "Unknown"
            }
        }
    }

    let compensationType: CompensationType
    let payPeriod: String?
    let rateAmount: Double?
    let rateLabel: String?
    let payDate: Date?

    init?(row: [String: Any]) {
        let typeValue = TimeClockCompensationProfile.string(in: row, keys: [
            "compensation_type",
            "pay_type",
            "employee_type",
            "rate_type",
            "salary_type"
        ])

        let inferredType: CompensationType
        let normalizedType = typeValue?
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch normalizedType {
        case "salary", "salaried", "salary employee", "salaried employee":
            inferredType = .salary
        case "daily", "day", "day rate", "daily employee":
            inferredType = .daily
        case "hourly", "hour", "hour rate", "hourly employee":
            inferredType = .hourly
        default:
            if TimeClockCompensationProfile.bool(in: row, keys: ["is_salary"]) == true {
                inferredType = .salary
            } else {
                inferredType = .unknown
            }
        }

        let payPeriod = TimeClockCompensationProfile.string(in: row, keys: [
            "pay_period_type",
            "pay_period",
            "pay_schedule",
            "pay_frequency"
        ])

        let salary = TimeClockCompensationProfile.double(in: row, keys: [
            "salary",
            "pay_amount",
            "compensation_amount",
            "salary_amount",
            "annual_salary"
        ])
        let legacyDailyAmount = TimeClockCompensationProfile.double(in: row, keys: [
            "daily_salary",
            "daily_rate",
            "day_rate",
            "daily_pay",
            "day_pay"
        ])
        let legacyHourlyAmount = TimeClockCompensationProfile.double(in: row, keys: [
            "hourly_wage",
            "hourly_rate",
            "hour_rate",
            "hourly_pay",
            "wage",
            "wage_rate"
        ])
        let genericRate = TimeClockCompensationProfile.double(in: row, keys: ["pay_rate", "rate"])

        let resolvedAmount: Double?
        let resolvedRateLabel: String?
        switch inferredType {
        case .salary:
            resolvedAmount = salary ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Salary"
        case .daily:
            resolvedAmount = salary ?? legacyDailyAmount ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Daily Rate"
        case .hourly:
            resolvedAmount = salary ?? legacyHourlyAmount ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Hourly Rate"
        case .unknown:
            resolvedAmount = salary ?? genericRate ?? legacyHourlyAmount ?? legacyDailyAmount
            resolvedRateLabel = resolvedAmount == nil ? nil : "Rate"
        }

        let payDate = TimeClockCompensationProfile.date(in: row, keys: [
            "pay_date",
            "next_pay_date",
            "upcoming_pay_date",
            "last_pay_date"
        ])

        guard inferredType != .unknown || payPeriod != nil || resolvedAmount != nil || payDate != nil else {
            return nil
        }

        self.compensationType = inferredType
        self.payPeriod = payPeriod
        self.rateAmount = resolvedAmount
        self.rateLabel = resolvedRateLabel
        self.payDate = payDate
    }

    func payPeriodRange(referenceDate: Date = Date(), calendar: Calendar = .current) -> DateInterval? {
        guard let payPeriod else { return nil }

        let value = payPeriod.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        switch value {
        case "weekly", "week":
            return calendar.dateInterval(of: .weekOfYear, for: referenceDate)
        case "biweekly", "bi weekly", "every 2 weeks":
            guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: referenceDate) else { return nil }
            let referenceAnchor = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1)) ?? weekRange.start
            let weeks = calendar.dateComponents([.weekOfYear], from: referenceAnchor, to: weekRange.start).weekOfYear ?? 0
            if weeks.isMultiple(of: 2) {
                guard let end = calendar.date(byAdding: .day, value: 14, to: weekRange.start) else { return nil }
                return DateInterval(start: weekRange.start, end: end)
            } else {
                guard
                    let start = calendar.date(byAdding: .day, value: -7, to: weekRange.start),
                    let end = calendar.date(byAdding: .day, value: 7, to: weekRange.start)
                else { return nil }
                return DateInterval(start: start, end: end)
            }
        case "semi monthly", "semimonthly", "twice monthly":
            let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }
            if day <= 15 {
                guard
                    let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                    let end = calendar.date(from: DateComponents(year: year, month: month, day: 16))
                else { return nil }
                return DateInterval(start: start, end: end)
            } else {
                guard
                    let start = calendar.date(from: DateComponents(year: year, month: month, day: 16)),
                    let nextMonth = calendar.date(byAdding: .month, value: 1, to: start),
                    let end = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth))
                else { return nil }
                return DateInterval(start: start, end: end)
            }
        case "monthly", "month":
            return calendar.dateInterval(of: .month, for: referenceDate)
        default:
            return nil
        }
    }

    func earned(forSessionHours hours: Double, shouldPayDailyRateForDay: Bool = true) -> Double? {
        guard let rateAmount, hours > 0 else { return nil }

        let earned: Double
        switch compensationType {
        case .hourly:
            earned = rateAmount * hours
        case .daily:
            guard shouldPayDailyRateForDay else { return nil }
            earned = rateAmount
        case .salary:
            return nil
        case .unknown:
            return nil
        }

        return (earned * 100).rounded() / 100
    }
 
    // Original current pay period april 16 - april 30, 2026
 //   var currentPayPeriodText: String? {
 //       guard let interval = payPeriodRange() else { return nil }
 //       let formatter = DateFormatter()
 //       formatter.dateStyle = .medium
 //       formatter.timeStyle = .none

 //       let endDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
 //       return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endDate))"
 //  }
   
    
    var currentPayPeriodText: String? {
        guard let interval = payPeriodRange() else { return nil }
        
        let start = interval.start
        let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMM"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "d"
        
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = "yyyy"
        
        let startMonth = monthFormatter.string(from: start)
        let startDay = dayFormatter.string(from: start)
        let endDay = dayFormatter.string(from: end)
        let year = yearFormatter.string(from: end)  // use end date's year
        
        if startMonth == monthFormatter.string(from: end) {
            // Same month → "Apr 16 - 30, 2026"
            return "\(startMonth) \(startDay) - \(endDay), \(year)"
        } else {
            // Different months (rare for semi-monthly) → "Apr 16 - May 15, 2026"
            return "\(startMonth) \(startDay) - \(monthFormatter.string(from: end)) \(endDay), \(year)"
        }
    }

    func resolvedPayDate(referenceDate: Date = Date(), calendar: Calendar = .current) -> Date? {
        if let payDate {
            return adjustedForwardFromSunday(payDate, calendar: calendar)
        }

        guard let payPeriod else { return nil }
        let value = payPeriod.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)

        switch value {
        case "semi monthly", "semimonthly", "twice monthly":
            let components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            guard let year = components.year, let month = components.month, let day = components.day else { return nil }

            if day <= 15 {
                guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 16)) else {
                    return nil
                }
                return adjustedForwardFromSunday(date, calendar: calendar)
            } else {
                guard
                    let currentMonthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                    let nextMonth = calendar.date(byAdding: .month, value: 1, to: currentMonthDate)
                else { return nil }
                let nextComponents = calendar.dateComponents([.year, .month], from: nextMonth)
                guard let date = calendar.date(from: DateComponents(year: nextComponents.year, month: nextComponents.month, day: 1)) else {
                    return nil
                }
                return adjustedForwardFromSunday(date, calendar: calendar)
            }
        default:
            return payDate.map { adjustedForwardFromSunday($0, calendar: calendar) }
        }
    }

    private func adjustedForwardFromSunday(_ date: Date, calendar: Calendar) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        guard weekday == 1 else { return date }
        return calendar.date(byAdding: .day, value: 1, to: date) ?? date
    }

    private static func string(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = row[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func bool(in row: [String: Any], keys: [String]) -> Bool? {
        for key in keys {
            if let value = row[key] as? Bool {
                return value
            }
            if let value = row[key] as? NSNumber {
                return value.boolValue
            }
        }
        return nil
    }

    private static func double(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = row[key] as? Double {
                return value
            }
            if let value = row[key] as? NSNumber {
                return value.doubleValue
            }
            if let value = row[key] as? String, let parsed = Double(value) {
                return parsed
            }
        }
        return nil
    }

    private static func date(in row: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = row[key] as? String, let parsed = parseDate(value) {
                return parsed
            }
            if let value = row[key] as? Date {
                return value
            }
        }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let isoWithFractional = ISO8601DateFormatter()
        isoWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoWithFractional.date(from: value) {
            return date
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) {
            return date
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }
}
