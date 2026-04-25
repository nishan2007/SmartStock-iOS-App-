//
//  OperationsService.swift
//  SmartStock
//

import Foundation
import Supabase

struct OperationsService {
    private let client = supabase
    private let inventoryService = InventoryService()

    func fetchProduct(forBarcode barcode: String) async throws -> ScannedProduct? {
        guard let productId = try await inventoryService.productId(forBarcode: barcode) else {
            return nil
        }

        let rows: [ScannedProduct] = try await client
            .from("products")
            .select("product_id, name, sku, barcode, product_type")
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
            .select("product_id, name, sku, barcode, product_type")
            .or("name.ilike.%\(trimmedQuery)%,sku.ilike.%\(trimmedQuery)%")
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
                    productName: product.name,
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
        guard !items.isEmpty else {
            throw OperationsServiceError.invalidQuantity
        }

        let receiveNumber = await MainActor.run {
            ReceiptNumberManager.shared.nextReceive(for: store.id)
        }

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

        for item in items {
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

        let summaryName: String
        if items.count == 1 {
            summaryName = items[0].productName
        } else {
            summaryName = "\(items.count) items"
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
                    productName: product.name,
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
                .select("transfer_item_id, product_id, quantity, product:products(name, sku)")
                .eq("transfer_id", value: Int(row.transfer_id))
                .order("transfer_item_id", ascending: true)
                .execute()
                .value

            let items = itemRows.map {
                IncomingStoreTransferItem(
                    transferItemId: $0.transfer_item_id,
                    productId: $0.product_id,
                    productName: $0.product?.name ?? "Unknown Product",
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

        let receiveNumber = await MainActor.run {
            ReceiptNumberManager.shared.nextReceive(for: receivingStore.id)
        }

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
            .select("sale_item_id, sale_id, product_id, quantity, unit_price, products(name)")
            .eq("sale_id", value: sale.sale_id)
            .eq("product_id", value: productId)
            .execute()
            .value

        guard let item = items.first else {
            throw OperationsServiceError.saleItemNotFound
        }

        return ReturnSaleLookupResult(sale: sale, item: item)
    }

    func createReturn(
        sale: ReturnLookupSale,
        item: ReturnableSaleItem,
        quantity: Int,
        reason: String,
        restockItem: Bool,
        store: Store,
        user: AppUser
    ) async throws -> ReturnResult {
        guard quantity > 0 else {
            throw OperationsServiceError.invalidQuantity
        }
        guard quantity <= item.quantity else {
            throw OperationsServiceError.returnQuantityTooHigh
        }

        let refundAmount = Double(quantity) * (item.unit_price ?? 0)
        let insertedReturn: InsertedSaleReturn = try await client
            .from("sale_returns")
            .insert(
                NewSaleReturn(
                    sale_id: sale.sale_id,
                    location_id: store.id,
                    user_id: user.id,
                    user_name: user.fullName,
                    refund_method: "ORIGINAL",
                    refund_amount: refundAmount,
                    reason: reason,
                    device_id: await MainActor.run { ReceiptNumberManager.shared.currentDeviceId() }
                )
            )
            .select("return_id")
            .single()
            .execute()
            .value

        _ = try await client
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
            .execute()

        _ = try await client
            .from("sales")
            .update(SaleReturnedAmountUpdate(returned_amount: (sale.returned_amount ?? 0) + refundAmount))
            .eq("sale_id", value: sale.sale_id)
            .execute()

        if restockItem {
            let existingInventory = try await fetchInventoryRecord(productId: item.product_id, locationId: store.id)
            let newQuantity = (existingInventory?.quantity_on_hand ?? 0) + quantity

            if let existingInventory {
                _ = try await client
                    .from("inventory")
                    .update(InventoryQuantityUpdate(quantity_on_hand: newQuantity))
                    .eq("inventory_id", value: existingInventory.inventory_id)
                    .execute()
            } else {
                _ = try await client
                    .from("inventory")
                    .insert(NewInventoryRecord(product_id: item.product_id, location_id: store.id, quantity_on_hand: quantity))
                    .execute()
            }

            _ = try await client
                    .from("inventory_movements")
                    .insert(
                    OperationInventoryMovement(
                        product_id: item.product_id,
                        location_id: store.id,
                        change_qty: quantity,
                        reason: "return",
                        note: "Return #\(insertedReturn.return_id) for sale #\(sale.sale_id)",
                        receive_id: nil,
                        receive_device_id: nil,
                        receive_sequence: nil,
                        user_name: user.fullName
                    )
                )
                .execute()
        }

        return ReturnResult(returnId: insertedReturn.return_id, refundAmount: refundAmount, productName: item.productName)
    }

    func fetchOpenTimeClockEntry(userId: Int) async throws -> TimeClockEntry? {
        let rows: [TimeClockEntry] = try await client
            .from("employee_time_clock")
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
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
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
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
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
            .single()
            .execute()
            .value

        return entry
    }

    func clockOut(entryId: Int64) async throws -> TimeClockEntry {
        let entry: TimeClockEntry = try await client
            .from("employee_time_clock")
            .update(TimeClockOutUpdate(clock_out: ISO8601DateFormatter().string(from: Date())))
            .eq("clock_id", value: Int(entryId))
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
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
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
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
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
            .single()
            .execute()
            .value

        return entry
    }

    func fetchEndOfDayReport(storeId: Int, for date: Date = Date()) async throws -> EndOfDayReport {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw OperationsServiceError.unexpectedResponse
        }

        let iso = ISO8601DateFormatter()
        let startValue = iso.string(from: startOfDay)
        let endValue = iso.string(from: endOfDay)

        let sales: [EndOfDaySaleRow] = try await client
            .from("sales")
            .select("sale_id, receipt_number, created_at, payment_method, payment_status, amount_paid, discount_amount, total_amount, user_name, receipt_device_id")
            .eq("location_id", value: storeId)
            .gte("created_at", value: startValue)
            .lt("created_at", value: endValue)
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

        let customerPayments: [EndOfDayCustomerPaymentRow] = try await client
            .from("customer_account_transactions")
            .select("transaction_id, payment_id, amount, note, created_at, user_name, customer_accounts(name)")
            .eq("transaction_type", value: "PAYMENT")
            .eq("location_id", value: storeId)
            .gte("created_at", value: startValue)
            .lt("created_at", value: endValue)
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

        let customerPaymentCash = customerPayments.reduce(0.0) { $0 + abs($1.amount ?? 0) }
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
            .select("clock_id, user_id, user_name, location_id, location_name, work_date, clock_in, lunch_start, lunch_end, clock_out")
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
                .select("sale_id, receipt_number, returned_amount")
                .eq("sale_id", value: saleId)
                .eq("location_id", value: storeId)
                .limit(1)
                .execute()
                .value
            return rows.first
        }

        let rows: [ReturnLookupSale] = try await client
            .from("sales")
            .select("sale_id, receipt_number, returned_amount")
            .eq("receipt_number", value: query)
            .eq("location_id", value: storeId)
            .limit(1)
            .execute()
            .value
        return rows.first
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
    let sku: String?
    let barcode: String?
    let productType: String?

    enum CodingKeys: String, CodingKey {
        case id = "product_id"
        case name
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
    let sku: String?
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
}

struct ReturnableProductName: Decodable {
    let name: String?
}

struct ReturnableSaleItem: Decodable {
    let sale_item_id: Int
    let sale_id: Int
    let product_id: Int
    let quantity: Int
    let unit_price: Double?
    let products: ReturnableProductName?

    var productName: String {
        products?.name ?? "Unknown Product"
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

    var isOpen: Bool {
        clockOut == nil
    }

    var isOnLunch: Bool {
        lunchStart != nil && lunchEnd == nil && clockOut == nil
    }

    func workedHours(until now: Date = Date()) -> Double {
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
        switch typeValue?.lowercased() {
        case "salary", "salaried":
            inferredType = .salary
        case "daily", "day", "day_rate":
            inferredType = .daily
        case "hourly", "hour", "hour_rate":
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

        let salaryAmount = TimeClockCompensationProfile.double(in: row, keys: ["salary_amount", "salary", "annual_salary"])
        let dailyAmount = TimeClockCompensationProfile.double(in: row, keys: ["daily_rate", "day_rate"])
        let hourlyAmount = TimeClockCompensationProfile.double(in: row, keys: ["hourly_rate", "hour_rate", "wage"])
        let genericRate = TimeClockCompensationProfile.double(in: row, keys: ["pay_rate", "rate"])

        let resolvedAmount: Double?
        let resolvedRateLabel: String?
        switch inferredType {
        case .salary:
            resolvedAmount = salaryAmount ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Salary"
        case .daily:
            resolvedAmount = dailyAmount ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Daily Rate"
        case .hourly:
            resolvedAmount = hourlyAmount ?? genericRate
            resolvedRateLabel = resolvedAmount == nil ? nil : "Hourly Rate"
        case .unknown:
            resolvedAmount = genericRate ?? hourlyAmount ?? dailyAmount ?? salaryAmount
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

    var currentPayPeriodText: String? {
        guard let interval = payPeriodRange() else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let endDate = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\(formatter.string(from: interval.start)) - \(formatter.string(from: endDate))"
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
