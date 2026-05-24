//
//  CustomOrderService.swift
//  SmartStock
//

import Foundation
import Supabase

struct CustomOrderService {
    private let client = supabase

    enum OrderScope {
        case myOrders(userId: Int)
        case assigned(userId: Int)
        case all
        case manager(locationId: Int?)
        case lookup(String)
    }

    func fetchItems(activeOnly: Bool = false) async throws -> [CustomOrderItem] {
        if activeOnly {
            return try await client
                .from("custom_order_items")
                .select(itemSelection)
                .eq("is_active", value: true)
                .order("item_name", ascending: true)
                .execute()
                .value
        }

        return try await client
            .from("custom_order_items")
            .select(itemSelection)
            .order("item_name", ascending: true)
            .execute()
            .value
    }

    func fetchVariants(customItemId: Int64, activeOnly: Bool = true) async throws -> [CustomOrderItemVariant] {
        let variants: [CustomOrderItemVariant] = try await client
            .from("custom_order_item_variants")
            .select("custom_variant_id, custom_item_id, variant_name, sku, barcode, fixed_price, quantity_on_hand, reorder_level, sold_quantity, image_url, is_active")
            .eq("custom_item_id", value: String(customItemId))
            .order("variant_name", ascending: true)
            .execute()
            .value

        return activeOnly ? variants.filter(\.isActive) : variants
    }

    func fetchItemMovements(customItemId: Int64) async throws -> [CustomOrderItemMovement] {
        try await client
            .from("custom_order_item_movements")
            .select("movement_id, custom_item_id, custom_variant_id, variant_name, change_qty, reason, note, user_name, receive_id, receive_device_id, receive_sequence, created_at")
            .eq("custom_item_id", value: String(customItemId))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchItemBarcodes(customItemId: Int64) async throws -> [CustomOrderItemBarcode] {
        try await client
            .from("custom_order_item_barcodes")
            .select("custom_item_barcode_id, custom_item_id, barcode, created_at")
            .eq("custom_item_id", value: String(customItemId))
            .order("barcode", ascending: true)
            .execute()
            .value
    }

    func fetchPrintMaterials(activeOnly: Bool = true) async throws -> [CustomOrderPrintMaterial] {
        if activeOnly {
            return try await client
                .from("custom_order_print_materials")
                .select("print_material_id, material_name, description, pricing_mode, is_active")
                .eq("is_active", value: true)
                .order("material_name", ascending: true)
                .execute()
                .value
        }

        return try await client
            .from("custom_order_print_materials")
            .select("print_material_id, material_name, description, pricing_mode, is_active")
            .order("material_name", ascending: true)
            .execute()
            .value
    }

    func fetchPrintSizePresets(activeOnly: Bool = true) async throws -> [CustomOrderPrintSizePreset] {
        if activeOnly {
            return try await client
                .from("custom_order_print_size_presets")
                .select("print_size_preset_id, print_material_id, preset_name, fixed_price, pricing_mode, is_active")
                .eq("is_active", value: true)
                .order("preset_name", ascending: true)
                .execute()
                .value
        }

        return try await client
            .from("custom_order_print_size_presets")
            .select("print_size_preset_id, print_material_id, preset_name, fixed_price, pricing_mode, is_active")
            .order("preset_name", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func savePrintMaterial(_ draft: CustomOrderPrintMaterialDraft, existingMaterialId: Int64? = nil) async throws -> Int64 {
        let trimmedName = draft.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CustomOrderServiceError.missingPrintMaterialName }

        let payload = CustomOrderPrintMaterialUpsert(
            material_name: trimmedName,
            description: normalized(draft.description),
            pricing_mode: draft.pricingMode,
            is_active: draft.isActive
        )

        if let existingMaterialId {
            _ = try await client
                .from("custom_order_print_materials")
                .update(payload)
                .eq("print_material_id", value: String(existingMaterialId))
                .execute()
            return existingMaterialId
        }

        let inserted: CustomOrderPrintMaterialIdRow = try await client
            .from("custom_order_print_materials")
            .insert(payload)
            .select("print_material_id")
            .single()
            .execute()
            .value
        return inserted.print_material_id
    }

    func deactivatePrintMaterial(materialId: Int64) async throws {
        _ = try await client
            .from("custom_order_print_materials")
            .update(["is_active": false])
            .eq("print_material_id", value: String(materialId))
            .execute()
    }

    @discardableResult
    func savePrintSizePreset(_ draft: CustomOrderPrintSizePresetDraft, materialId: Int64, existingPresetId: Int64? = nil) async throws -> Int64 {
        let trimmedName = draft.presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CustomOrderServiceError.missingPrintPresetName }
        let price = Double(draft.fixedPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let price, price >= 0 else { throw CustomOrderServiceError.invalidPrintPresetPrice }

        let payload = CustomOrderPrintSizePresetUpsert(
            print_material_id: materialId,
            preset_name: trimmedName,
            fixed_price: price,
            pricing_mode: draft.pricingMode,
            is_active: draft.isActive
        )

        if let existingPresetId {
            _ = try await client
                .from("custom_order_print_size_presets")
                .update(payload)
                .eq("print_size_preset_id", value: String(existingPresetId))
                .execute()
            return existingPresetId
        }

        let inserted: CustomOrderPrintSizePresetIdRow = try await client
            .from("custom_order_print_size_presets")
            .insert(payload)
            .select("print_size_preset_id")
            .single()
            .execute()
            .value
        return inserted.print_size_preset_id
    }

    func deactivatePrintSizePreset(presetId: Int64) async throws {
        _ = try await client
            .from("custom_order_print_size_presets")
            .update(["is_active": false])
            .eq("print_size_preset_id", value: String(presetId))
            .execute()
    }

    func fetchDesignPlacements(activeOnly: Bool = true) async throws -> [CustomOrderDesignPlacement] {
        if activeOnly {
            return try await client
                .from("custom_order_design_placements")
                .select("design_placement_id, placement_name, sort_order, is_active")
                .eq("is_active", value: true)
                .order("sort_order", ascending: true)
                .order("placement_name", ascending: true)
                .execute()
                .value
        }

        return try await client
            .from("custom_order_design_placements")
            .select("design_placement_id, placement_name, sort_order, is_active")
            .order("sort_order", ascending: true)
            .order("placement_name", ascending: true)
            .execute()
            .value
    }

    func fetchCompanyPreferences(locationId: Int?) async throws -> CustomOrderCompanyPreferences {
        let columns = """
        company_name,
        receipt_logo_url,
        receipt_header_line,
        receipt_footer_line,
        show_receipt_logo,
        show_sale_id_on_receipt,
        show_device_id_on_receipt,
        show_customer_on_receipt,
        show_sku_on_receipt,
        show_item_discounts_on_receipt,
        show_payment_status_on_receipt,
        next_receipt_counter,
        custom_order_slip_enabled,
        custom_order_slip_auto_print,
        custom_order_slip_title,
        custom_order_slip_contact_line,
        custom_order_slip_email_line,
        custom_order_slip_footer_note,
        custom_order_slip_blank_detail_lines,
        custom_order_slip_show_logo,
        custom_order_slip_show_order_number,
        custom_order_slip_show_due_date,
        custom_order_slip_show_customer_phone,
        custom_order_slip_show_customer_account,
        custom_order_slip_show_store,
        custom_order_slip_show_device,
        custom_order_slip_show_cashier,
        custom_order_slip_show_line_items,
        custom_order_slip_show_pricing,
        custom_order_slip_show_payment_summary,
        custom_order_slip_show_payment_reference,
        custom_order_slip_show_taken_by,
        custom_order_slip_show_signatures,
        custom_order_minimum_deposit_percent,
        custom_order_refund_approval_limit
        """

        if let locationId {
            let rows: [CustomOrderCompanyPreferences] = try await client
                .from("company_customization")
                .select(columns)
                .eq("location_id", value: locationId)
                .limit(1)
                .execute()
                .value
            if let row = rows.first { return row }
        }

        let rows: [CustomOrderCompanyPreferences] = try await client
            .from("company_customization")
            .select(columns)
            .is("location_id", value: nil)
            .limit(1)
            .execute()
            .value
        return rows.first ?? CustomOrderCompanyPreferences(customOrderMinimumDepositPercent: 0, customOrderRefundApprovalLimit: 0)
    }

    func saveCompanyPreferences(_ preferences: CustomOrderCompanyPreferences, locationId: Int?) async throws {
        let payload = CompanyCustomizationUpsert(
            location_id: locationId,
            company_name: preferences.companyName,
            receipt_logo_url: preferences.receiptLogoURL,
            receipt_header_line: preferences.receiptHeaderLine,
            receipt_footer_line: preferences.receiptFooterLine,
            show_receipt_logo: preferences.showReceiptLogo,
            show_sale_id_on_receipt: preferences.showSaleIdOnReceipt,
            show_device_id_on_receipt: preferences.showDeviceIdOnReceipt,
            show_customer_on_receipt: preferences.showCustomerOnReceipt,
            show_sku_on_receipt: preferences.showSkuOnReceipt,
            show_item_discounts_on_receipt: preferences.showItemDiscountsOnReceipt,
            show_payment_status_on_receipt: preferences.showPaymentStatusOnReceipt,
            next_receipt_counter: preferences.nextReceiptCounter,
            custom_order_slip_enabled: preferences.customOrderSlipEnabled,
            custom_order_slip_auto_print: preferences.customOrderSlipAutoPrint,
            custom_order_slip_title: preferences.customOrderSlipTitle,
            custom_order_slip_contact_line: preferences.customOrderSlipContactLine,
            custom_order_slip_email_line: preferences.customOrderSlipEmailLine,
            custom_order_slip_footer_note: preferences.customOrderSlipFooterNote,
            custom_order_slip_blank_detail_lines: preferences.customOrderSlipBlankDetailLines,
            custom_order_slip_show_logo: preferences.customOrderSlipShowLogo,
            custom_order_slip_show_order_number: preferences.customOrderSlipShowOrderNumber,
            custom_order_slip_show_due_date: preferences.customOrderSlipShowDueDate,
            custom_order_slip_show_customer_phone: preferences.customOrderSlipShowCustomerPhone,
            custom_order_slip_show_customer_account: preferences.customOrderSlipShowCustomerAccount,
            custom_order_slip_show_store: preferences.customOrderSlipShowStore,
            custom_order_slip_show_device: preferences.customOrderSlipShowDevice,
            custom_order_slip_show_cashier: preferences.customOrderSlipShowCashier,
            custom_order_slip_show_line_items: preferences.customOrderSlipShowLineItems,
            custom_order_slip_show_pricing: preferences.customOrderSlipShowPricing,
            custom_order_slip_show_payment_summary: preferences.customOrderSlipShowPaymentSummary,
            custom_order_slip_show_payment_reference: preferences.customOrderSlipShowPaymentReference,
            custom_order_slip_show_taken_by: preferences.customOrderSlipShowTakenBy,
            custom_order_slip_show_signatures: preferences.customOrderSlipShowSignatures,
            custom_order_minimum_deposit_percent: preferences.customOrderMinimumDepositPercent,
            custom_order_refund_approval_limit: preferences.customOrderRefundApprovalLimit
        )

        _ = try await client
            .from("company_customization")
            .upsert(payload, onConflict: "location_id")
            .execute()
    }

    func searchReceivingItem(_ query: String) async throws -> ReceivingLookupItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let product = try await OperationsService().searchProduct(trimmed) {
            return .product(product)
        }

        let selection = try await searchCustomOrderItemSelection(trimmed)
        if let customItem = selection.item, let variant = selection.variant {
            return .customVariant(item: customItem, variant: variant)
        }

        if let customItem = selection.item {
            return .customItem(customItem)
        }

        return nil
    }

    func searchCustomOrderItem(_ query: String) async throws -> CustomOrderItem? {
        try await searchCustomOrderItemSelection(query).item
    }

    func searchCustomOrderItemSelection(_ query: String) async throws -> CustomOrderItemSelectionResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return CustomOrderItemSelectionResult(item: nil, variant: nil) }

        if trimmed.uppercased().hasPrefix("CUSTOM-"),
           let id = Int64(trimmed.dropFirst("CUSTOM-".count)) {
            let rows: [CustomOrderItem] = try await client
                .from("custom_order_items")
                .select(itemSelection)
                .eq("custom_item_id", value: String(id))
                .limit(1)
                .execute()
                .value
            if let item = rows.first { return CustomOrderItemSelectionResult(item: item, variant: nil) }
        }

        let variantRows: [CustomOrderVariantLookupRow] = try await client
            .from("custom_order_item_variants")
            .select("custom_item_id, custom_variant_id")
            .or("sku.eq.\(trimmed.uppercased()),barcode.eq.\(trimmed),variant_name.ilike.%\(trimmed)%")
            .order("variant_name", ascending: true)
            .limit(1)
            .execute()
            .value

        if let variantMatch = variantRows.first {
            let itemRows: [CustomOrderItem] = try await client
                .from("custom_order_items")
                .select(itemSelection)
                .eq("custom_item_id", value: String(variantMatch.custom_item_id))
                .limit(1)
                .execute()
                .value
            if let item = itemRows.first {
                let fetchedVariants = try await fetchVariants(customItemId: item.customItemId, activeOnly: false)
                let variant = item.variants.first { $0.variantId == variantMatch.custom_variant_id }
                    ?? fetchedVariants.first { $0.variantId == variantMatch.custom_variant_id }
                return CustomOrderItemSelectionResult(item: item, variant: variant)
            }
        }

        let directRows: [CustomOrderItem] = try await client
            .from("custom_order_items")
            .select(itemSelection)
            .or("item_name.ilike.%\(trimmed)%,sku.eq.\(trimmed.uppercased()),barcode.eq.\(trimmed)")
            .order("item_name", ascending: true)
            .limit(1)
            .execute()
            .value

        if let item = directRows.first { return CustomOrderItemSelectionResult(item: item, variant: nil) }

        let barcodeRows: [CustomOrderItemBarcodeLookup] = try await client
            .from("custom_order_item_barcodes")
            .select("custom_item_id")
            .eq("barcode", value: trimmed)
            .limit(1)
            .execute()
            .value

        guard let barcodeMatch = barcodeRows.first else { return CustomOrderItemSelectionResult(item: nil, variant: nil) }

        let rows: [CustomOrderItem] = try await client
            .from("custom_order_items")
            .select(itemSelection)
            .eq("custom_item_id", value: String(barcodeMatch.custom_item_id))
            .limit(1)
            .execute()
            .value

        return CustomOrderItemSelectionResult(item: rows.first, variant: nil)
    }

    @discardableResult
    func saveItem(_ draft: CustomOrderItemDraft, existingItemId: Int64? = nil) async throws -> CustomOrderItemSaveResult {
        let trimmedName = draft.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CustomOrderServiceError.missingItemName }

        let fixedPrice = Double(draft.fixedPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        if draft.pricingType == .fixed && !draft.hasVariants && fixedPrice == nil { throw CustomOrderServiceError.invalidFixedPrice }
        let areaPrice = Double(draft.areaPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        if draft.pricingType == .area && !draft.hasVariants && areaPrice == nil { throw CustomOrderServiceError.invalidAreaPrice }

        let payload = CustomOrderItemUpsert(
            item_name: trimmedName,
            barcode: normalized(draft.barcode),
            description: normalized(draft.description),
            product_type: draft.itemType.rawValue,
            pricing_type: draft.pricingType.rawValue,
            fixed_price: draft.pricingType == .fixed && !draft.hasVariants ? fixedPrice : nil,
            area_price: draft.pricingType == .area && !draft.hasVariants ? areaPrice : nil,
            area_price_unit: draft.pricingType == .area ? normalized(draft.areaPriceUnit) : nil,
            dimension_unit: draft.pricingType == .area ? normalized(draft.dimensionUnit) : nil,
            max_width: draft.pricingType == .area ? Double(draft.maxWidth.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            max_length: draft.pricingType == .area ? Double(draft.maxLength.trimmingCharacters(in: .whitespacesAndNewlines)) : nil,
            image_url: draft.hasVariants ? nil : normalized(draft.imageUrl),
            quantity_on_hand: draft.hasVariants ? 0 : (Double(draft.quantityOnHand.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0),
            reorder_level: draft.hasVariants ? 0 : (Double(draft.reorderLevel.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0),
            has_variants: draft.hasVariants,
            is_active: draft.isActive
        )

        if let existingItemId {
            let updated: CustomOrderItemSaveResult = try await client
                .from("custom_order_items")
                .update(payload)
                .eq("custom_item_id", value: String(existingItemId))
                .select("custom_item_id, sku")
                .single()
                .execute()
                .value
            return updated
        } else {
            let inserted: CustomOrderItemSaveResult = try await client
                .from("custom_order_items")
                .insert(payload)
                .select("custom_item_id, sku")
                .single()
                .execute()
                .value
            return inserted
        }
    }

    @discardableResult
    func saveVariant(_ draft: CustomOrderVariantDraft, customItemId: Int64, existingVariantId: Int64? = nil, requiresPrice: Bool = false) async throws -> CustomOrderVariantSaveResult? {
        let trimmedName = draft.variantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw CustomOrderServiceError.missingVariantName }
        let fixedPrice = Double(draft.fixedPrice.trimmingCharacters(in: .whitespacesAndNewlines))
        if requiresPrice && fixedPrice == nil { throw CustomOrderServiceError.invalidVariantPrice }

        let payload = CustomOrderVariantUpsert(
            custom_item_id: customItemId,
            variant_name: trimmedName,
            barcode: normalized(draft.barcode),
            fixed_price: fixedPrice,
            quantity_on_hand: Double(draft.quantityOnHand.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            reorder_level: Double(draft.reorderLevel.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0,
            image_url: normalized(draft.imageUrl),
            is_active: draft.isActive
        )

        let savedVariant: CustomOrderVariantSaveResult?
        if let existingVariantId {
            savedVariant = try await client
                .from("custom_order_item_variants")
                .update(payload)
                .eq("custom_variant_id", value: String(existingVariantId))
                .select("custom_variant_id, sku")
                .single()
                .execute()
                .value
        } else {
            savedVariant = try await client
                .from("custom_order_item_variants")
                .insert(payload)
                .select("custom_variant_id, sku")
                .single()
                .execute()
                .value
        }

        _ = try await client
            .from("custom_order_items")
            .update(CustomOrderItemHasVariantsUpdate(has_variants: true))
            .eq("custom_item_id", value: String(customItemId))
            .execute()

        return savedVariant
    }

    func addItemBarcode(customItemId: Int64, barcode: String) async throws {
        guard let normalizedBarcode = normalized(barcode) else { return }
        _ = try await client
            .from("custom_order_item_barcodes")
            .insert(CustomOrderItemBarcodeInsert(custom_item_id: customItemId, barcode: normalizedBarcode))
            .execute()
    }

    func deleteItemBarcode(_ barcodeId: Int64) async throws {
        _ = try await client
            .from("custom_order_item_barcodes")
            .delete()
            .eq("custom_item_barcode_id", value: String(barcodeId))
            .execute()
    }

    func deactivateItem(customItemId: Int64) async throws {
        _ = try await client
            .from("custom_order_items")
            .update(CustomOrderItemActiveUpdate(is_active: false))
            .eq("custom_item_id", value: String(customItemId))
            .execute()
    }

    func receiveCustomItems(_ items: [ReceiveCustomOrderItem], receiveNumber: ReceiveNumber, user: AppUser) async throws {
        for item in items {
            if let variantId = item.customVariantId {
                let rows: [CustomOrderVariantReceiveQuantityRow] = try await client
                    .from("custom_order_item_variants")
                    .select("custom_variant_id, custom_item_id, variant_name, quantity_on_hand")
                    .eq("custom_variant_id", value: String(variantId))
                    .limit(1)
                    .execute()
                    .value

                guard let existing = rows.first else { throw CustomOrderServiceError.customItemNotFound }

                _ = try await client
                    .from("custom_order_item_variants")
                    .update(CustomOrderQuantityUpdate(quantity_on_hand: existing.quantity_on_hand + Double(item.quantity)))
                    .eq("custom_variant_id", value: String(variantId))
                    .execute()

                _ = try await client
                    .from("custom_order_item_movements")
                    .insert(CustomOrderItemMovementInsert(custom_item_id: existing.custom_item_id, change_qty: Double(item.quantity), reason: "INVENTORY_ENTRY", note: "entered_by_user_id=\(user.id)", user_name: user.fullName, receive_id: receiveNumber.receiveId, receive_device_id: receiveNumber.deviceId, receive_sequence: receiveNumber.sequence, custom_variant_id: variantId, variant_name: item.variantName ?? existing.variant_name))
                    .execute()
                continue
            }

            let rows: [CustomOrderQuantityRow] = try await client
                .from("custom_order_items")
                .select("custom_item_id, quantity_on_hand")
                .eq("custom_item_id", value: String(item.customItemId))
                .limit(1)
                .execute()
                .value

            guard let existing = rows.first else { throw CustomOrderServiceError.customItemNotFound }

            _ = try await client
                .from("custom_order_items")
                .update(CustomOrderQuantityUpdate(quantity_on_hand: existing.quantity_on_hand + Double(item.quantity)))
                .eq("custom_item_id", value: String(item.customItemId))
                .execute()

            _ = try await client
                .from("custom_order_item_movements")
                .insert(CustomOrderItemMovementInsert(custom_item_id: item.customItemId, change_qty: Double(item.quantity), reason: "INVENTORY_ENTRY", note: "entered_by_user_id=\(user.id)", user_name: user.fullName, receive_id: receiveNumber.receiveId, receive_device_id: receiveNumber.deviceId, receive_sequence: receiveNumber.sequence))
                .execute()
        }
    }

    func fetchOrders(scope: OrderScope = .all) async throws -> [CustomOrder] {
        switch scope {
        case .myOrders(let userId):
            return try await client.from("custom_orders").select(orderSelection).eq("taken_by_user_id", value: userId).order("created_at", ascending: false).execute().value
        case .assigned(let userId):
            return try await client.from("custom_orders").select(orderSelection).eq("assigned_to_user_id", value: userId).order("created_at", ascending: false).execute().value
        case .manager(let locationId):
            if let locationId {
                return try await client.from("custom_orders").select(orderSelection).eq("location_id", value: locationId).order("created_at", ascending: false).execute().value
            }
            return try await client.from("custom_orders").select(orderSelection).order("created_at", ascending: false).execute().value
        case .lookup(let query):
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return [] }
            return try await client.from("custom_orders").select(orderSelection).or("order_number.ilike.%\(trimmed)%,customer_name.ilike.%\(trimmed)%,customer_phone.ilike.%\(trimmed)%").order("created_at", ascending: false).execute().value
        case .all:
            return try await client.from("custom_orders").select(orderSelection).order("created_at", ascending: false).execute().value
        }
    }

    func fetchOrder(orderId: Int64) async throws -> CustomOrder {
        try await client
            .from("custom_orders")
            .select(orderSelection)
            .eq("custom_order_id", value: String(orderId))
            .single()
            .execute()
            .value
    }

    func fetchCustomerAccount(customerId: Int) async throws -> CustomerAccount {
        try await client
            .from("customer_accounts")
            .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
            .eq("customer_id", value: String(customerId))
            .single()
            .execute()
            .value
    }

    func fetchRecentLookupOrders(query: String, locationId: Int?, daysBack: Int = 30) async throws -> [CustomOrder] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sinceDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
        let sinceValue = ISO8601DateFormatter().string(from: sinceDate)

        var request = client
            .from("custom_orders")
            .select(orderSelection)
            .or("order_number.ilike.%\(trimmed)%,customer_name.ilike.%\(trimmed)%,customer_phone.ilike.%\(trimmed)%")
            .gte("created_at", value: sinceValue)

        if let locationId {
            request = request.eq("location_id", value: locationId)
        }

        return try await request
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchAuditLog(orderId: Int64) async throws -> [CustomOrderAuditEntry] {
        try await client
            .from("custom_order_audit_log")
            .select("custom_order_audit_id, custom_order_id, action_type, field_name, old_value, new_value, reason, user_name, created_at, device_name")
            .eq("custom_order_id", value: String(orderId))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchStatusHistory(orderId: Int64) async throws -> [CustomOrderStatusHistoryEntry] {
        try await client
            .from("custom_order_status_history")
            .select("custom_order_status_history_id, custom_order_id, old_status, new_status, reason, user_name, created_at, device_name")
            .eq("custom_order_id", value: String(orderId))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchDeliveryHistory(orderId: Int64) async throws -> [CustomOrderLineDeliveryHistoryEntry] {
        try await client
            .from("custom_order_line_deliveries")
            .select("custom_order_line_delivery_id, custom_order_line_id, item_name, variant_name, delivered_by_name, delivery_notes, delivered_at, device_name")
            .eq("custom_order_id", value: String(orderId))
            .order("delivered_at", ascending: false)
            .execute()
            .value
    }

    func fetchProductionHistory(orderId: Int64) async throws -> [CustomOrderLineProductionHistoryEntry] {
        try await client
            .from("custom_order_line_production_history")
            .select("custom_order_line_production_history_id, custom_order_line_id, item_name, variant_name, old_status, new_status, notes, updated_by_name, created_at, device_name")
            .eq("custom_order_id", value: String(orderId))
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func createCustomerIfNeeded(customer: CustomerAccount?, customerName: String, customerPhone: String) async throws -> CustomerAccount {
        if let customer { return customer }
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = customerPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !phone.isEmpty else { throw CustomOrderServiceError.customerNeedsNameAndPhone }

        return try await client
            .from("customer_accounts")
            .insert(CustomOrderCustomerInsert(name: name, phone: phone, email: nil, customer_type_id: 1, is_active: true, is_business: false))
            .select("customer_id, account_number, name, phone, email, credit_limit, current_balance, is_active, is_business, account_notes, customer_type_id, created_at")
            .single()
            .execute()
            .value
    }

    func createOrder(
        customer: CustomerAccount?,
        customerName: String,
        customerPhone: String,
        dueDate: Date?,
        notes: String,
        lines: [CustomOrderDraftLine],
        paymentMethod: CustomOrderPaymentMethod?,
        paymentAmount: Double,
        paymentReference: String?,
        depositOverrideReason: String?,
        user: AppUser,
        store: Store?,
        device: TrackedDevice?
    ) async throws -> CustomOrderCreateResult {
        guard !lines.isEmpty else { throw CustomOrderServiceError.orderNeedsLine }

        let autoCreatedCustomer = customer == nil
        let resolvedCustomer = try await createCustomerIfNeeded(customer: customer, customerName: customerName, customerPhone: customerPhone)
        let preferences = try await fetchCompanyPreferences(locationId: store?.id)
        let minimumDepositRequired = lines.reduce(0) { $0 + $1.lineTotal } * preferences.customOrderMinimumDepositPercent / 100
        if paymentAmount + 0.0001 < minimumDepositRequired && normalized(depositOverrideReason) == nil {
            throw CustomOrderServiceError.depositOverrideReasonRequired
        }
        if let paymentMethod, paymentMethod.requiresReference, normalized(paymentReference) == nil {
            throw CustomOrderServiceError.paymentReferenceRequired
        }

        let resolvedLines = try lines.enumerated().map { index, draftLine -> CustomOrderLineInsertSeed in
            guard let unitPrice = draftLine.unitPrice, unitPrice >= 0 else { throw CustomOrderServiceError.variablePriceRequired }
            if draftLine.hasPriceOverride && normalized(draftLine.priceOverrideReason) == nil {
                throw CustomOrderServiceError.priceOverrideReasonRequired
            }
            if draftLine.discountPercent > 0 && normalized(draftLine.discountReason) == nil {
                throw CustomOrderServiceError.discountReasonRequired
            }
            return CustomOrderLineInsertSeed(line: draftLine, unitPrice: unitPrice, sortOrder: index)
        }

        let total = resolvedLines.reduce(0) { $0 + $1.line.lineTotal }
        let paid = min(max(paymentAmount, 0), total)
        let balanceDue = max(total - paid, 0)
        let paymentStatus: CustomOrderPaymentStatus = paid <= 0 ? .unpaid : (balanceDue > 0 ? .partial : .paid)
        let cashDrawer: ResolvedCashDrawer?
        if paymentMethod == .cash, paid > 0 {
            guard let store else { throw CashDrawerError.missingStore }
            cashDrawer = try await CashDrawerService().resolveAssignedDrawer(storeId: store.id, deviceId: device?.id)
        } else {
            cashDrawer = nil
        }

        let insertedOrder = try await insertCustomOrderWithRetry(
            customer: resolvedCustomer,
            customerPhone: customerPhone,
            dueDate: dueDate,
            notes: notes,
            total: total,
            paymentMethod: paymentMethod,
            paymentReference: paymentReference,
            paymentStatus: paymentStatus,
            paid: paid,
            balanceDue: balanceDue,
            minimumDepositRequired: minimumDepositRequired,
            depositOverrideReason: depositOverrideReason,
            user: user,
            store: store,
            device: device,
            cashDrawer: cashDrawer
        )

        try await writeAudit(orderId: insertedOrder.custom_order_id, action: "CREATE_ORDER", fieldName: "total_amount", oldValue: nil, newValue: String(format: "%.2f", total), reason: normalized(notes), user: user, device: device)
        try await writeStatusHistory(orderId: insertedOrder.custom_order_id, oldStatus: nil, newStatus: .new, reason: "Order created", user: user, device: device)
        if autoCreatedCustomer {
            try await writeAudit(orderId: insertedOrder.custom_order_id, action: "AUTO_CREATE_CUSTOMER", fieldName: "customer_id", oldValue: nil, newValue: "\(resolvedCustomer.customerId)", reason: "\(resolvedCustomer.name) / \(resolvedCustomer.phone ?? customerPhone)", user: user, device: device)
        }
        if paid + 0.0001 < minimumDepositRequired {
            try await writeAudit(orderId: insertedOrder.custom_order_id, action: "DEPOSIT_OVERRIDE", fieldName: "minimum_deposit_required", oldValue: String(format: "%.2f", minimumDepositRequired), newValue: String(format: "%.2f", paid), reason: normalized(depositOverrideReason), user: user, device: device)
        }

        for seed in resolvedLines {
            let lineId: CustomOrderLineIdRow = try await client
                .from("custom_order_lines")
                .insert(CustomOrderLineInsert(orderId: insertedOrder.custom_order_id, seed: seed, user: user))
                .select("custom_order_line_id")
                .single()
                .execute()
                .value

            try await writeAudit(orderId: insertedOrder.custom_order_id, action: "CREATE_LINE", fieldName: "custom_order_line_id", oldValue: nil, newValue: "\(lineId.custom_order_line_id)", reason: seed.line.item.itemName, user: user, device: device)
            if seed.line.item.pricingType == .area {
                try await writeAudit(orderId: insertedOrder.custom_order_id, action: "AREA_PRICE", fieldName: "custom_order_line_id", oldValue: nil, newValue: seed.line.areaText, reason: String(format: "$%.2f", seed.unitPrice), user: user, device: device)
            }
            if seed.line.hasPriceOverride {
                try await writeAudit(orderId: insertedOrder.custom_order_id, action: "PRICE_OVERRIDE", fieldName: "unit_price", oldValue: seed.line.basePrice.map { String(format: "%.2f", $0) }, newValue: String(format: "%.2f", seed.unitPrice), reason: normalized(seed.line.priceOverrideReason), user: user, device: device)
            }
            if seed.line.discountPercent > 0 {
                try await writeAudit(orderId: insertedOrder.custom_order_id, action: "LINE_DISCOUNT", fieldName: "line_discount_percent", oldValue: nil, newValue: String(format: "%.2f", seed.line.discountPercent), reason: normalized(seed.line.discountReason), user: user, device: device)
            }

            if !seed.line.printAddons.isEmpty {
                let addonRows = seed.line.printAddons.enumerated().map { index, addon in
                    CustomOrderLinePrintAddonInsert(custom_order_line_id: lineId.custom_order_line_id, print_material_id: addon.material?.materialId, print_material_name: addon.material?.materialName ?? "Print Add On", print_size_preset_id: addon.preset?.presetId, print_size_name: addon.preset?.presetName, pricing_mode: addon.pricingMode, print_charge: addon.price, print_line_count: addon.lineCount, sort_order: index + 1, print_description: normalized(addon.printDescription))
                }
                _ = try await client.from("custom_order_line_print_addons").insert(addonRows).execute()
                for addon in seed.line.printAddons {
                    try await writeAudit(orderId: insertedOrder.custom_order_id, action: "ADD_PRINT_ADDON", fieldName: "custom_order_line_id", oldValue: nil, newValue: "\(lineId.custom_order_line_id)", reason: "\(addon.material?.materialName ?? "Print Add On") \(String(format: "$%.2f", addon.price))", user: user, device: device)
                }
            }

            try await applySoldQuantity(seed.line, user: user)
        }

        if let paymentMethod, paid > 0 {
            let paymentId = try await recordCustomOrderPayment(
                orderId: insertedOrder.custom_order_id,
                amount: paid,
                method: paymentMethod,
                reference: paymentReference,
                user: user,
                device: device,
                cashDrawer: cashDrawer
            )
            try await recordCustomOrderPaymentLedger(
                customerId: resolvedCustomer.customerId,
                orderId: insertedOrder.custom_order_id,
                amount: paid,
                paymentId: paymentId,
                note: "Custom order payment. payment_method=\(paymentMethod.rawValue), custom_order_id=\(insertedOrder.custom_order_id), order_number=\(insertedOrder.order_number)",
                user: user,
                store: store,
                device: device,
                paymentMethod: paymentMethod,
                paymentReference: paymentReference,
                cashDrawer: cashDrawer
            )
            try await writeAudit(orderId: insertedOrder.custom_order_id, action: "ADD_PAYMENT", fieldName: "amount_paid", oldValue: "0.00", newValue: String(format: "%.2f", paid), reason: paymentMethod.title, user: user, device: device)
        }

        if balanceDue > 0 {
            try await chargeCustomOrderBalanceToAccount(
                customerId: resolvedCustomer.customerId,
                orderId: insertedOrder.custom_order_id,
                amount: balanceDue,
                note: "Custom order balance charged to account. custom_order_id=\(insertedOrder.custom_order_id), order_number=\(insertedOrder.order_number)",
                user: user,
                store: store,
                device: device
            )
            try await writeAudit(orderId: insertedOrder.custom_order_id, action: "ACCOUNT_CHARGE", fieldName: "balance_due", oldValue: nil, newValue: String(format: "%.2f", balanceDue), reason: "Charged to customer account", user: user, device: device)
        }

        return CustomOrderCreateResult(orderId: insertedOrder.custom_order_id, totalAmount: total)
    }

    private func insertCustomOrderWithRetry(
        customer: CustomerAccount,
        customerPhone: String,
        dueDate: Date?,
        notes: String,
        total: Double,
        paymentMethod: CustomOrderPaymentMethod?,
        paymentReference: String?,
        paymentStatus: CustomOrderPaymentStatus,
        paid: Double,
        balanceDue: Double,
        minimumDepositRequired: Double,
        depositOverrideReason: String?,
        user: AppUser,
        store: Store?,
        device: TrackedDevice?,
        cashDrawer: ResolvedCashDrawer?
    ) async throws -> CustomOrderIdRow {
        let baseMilliseconds = Self.orderNumberMilliseconds()
        var lastError: Error?

        for retryOffset in 0..<3 {
            let orderNumber = Self.orderNumber(milliseconds: baseMilliseconds + Int64(retryOffset))
            do {
                return try await insertCustomOrder(
                    orderNumber: orderNumber,
                    customer: customer,
                    customerPhone: customerPhone,
                    dueDate: dueDate,
                    notes: notes,
                    total: total,
                    paymentMethod: paymentMethod,
                    paymentReference: paymentReference,
                    paymentStatus: paymentStatus,
                    paid: paid,
                    balanceDue: balanceDue,
                    minimumDepositRequired: minimumDepositRequired,
                    depositOverrideReason: depositOverrideReason,
                    user: user,
                    store: store,
                    device: device,
                    cashDrawer: cashDrawer
                )
            } catch {
                guard Self.isDuplicateOrderNumberError(error) else { throw error }
                lastError = error
            }
        }

        throw CustomOrderServiceError.orderNumberGenerationFailed(lastError?.localizedDescription)
    }

    private func insertCustomOrder(
        orderNumber: String,
        customer: CustomerAccount,
        customerPhone: String,
        dueDate: Date?,
        notes: String,
        total: Double,
        paymentMethod: CustomOrderPaymentMethod?,
        paymentReference: String?,
        paymentStatus: CustomOrderPaymentStatus,
        paid: Double,
        balanceDue: Double,
        minimumDepositRequired: Double,
        depositOverrideReason: String?,
        user: AppUser,
        store: Store?,
        device: TrackedDevice?,
        cashDrawer: ResolvedCashDrawer?
    ) async throws -> CustomOrderIdRow {
        try await client
            .from("custom_orders")
            .insert(CustomOrderInsert(
                order_number: orderNumber,
                customer_id: customer.customerId,
                customer_name: customer.name,
                customer_phone: customer.phone ?? customerPhone,
                status: CustomOrderStatus.new.rawValue,
                due_date: dueDate.map(Self.dateFormatter.string(from:)),
                order_notes: normalized(notes),
                total_amount: total,
                payment_method: paymentMethod?.rawValue,
                payment_reference: normalized(paymentReference),
                cash_drawer_id: cashDrawer?.drawerId,
                cash_drawer_name: cashDrawer?.drawerName,
                payment_status: paymentStatus.rawValue,
                amount_paid: paid,
                balance_due: balanceDue,
                minimum_deposit_required: minimumDepositRequired,
                deposit_override_reason: paid + 0.0001 < minimumDepositRequired ? normalized(depositOverrideReason) : nil,
                deposit_override_by_user_id: paid + 0.0001 < minimumDepositRequired ? user.id : nil,
                deposit_override_by_name: paid + 0.0001 < minimumDepositRequired ? user.fullName : nil,
                location_id: store?.id,
                location_name: store?.name,
                device_id: device?.id.uuidString,
                device_name: device?.deviceName ?? device?.modelName,
                taken_by_user_id: user.id,
                taken_by_name: user.fullName
            ))
            .select("custom_order_id, order_number")
            .single()
            .execute()
            .value
    }

    func fetchEmployees() async throws -> [CustomOrderEmployee] {
        try await client.from("users").select("user_id, full_name, username").eq("is_active", value: true).order("full_name", ascending: true).execute().value
    }

    func assignOrder(_ order: CustomOrder, to employee: CustomOrderEmployee, by manager: AppUser, device: TrackedDevice?) async throws {
        let status = order.status == .new ? CustomOrderStatus.assigned.rawValue : order.status.rawValue
        _ = try await client.from("custom_orders").update(CustomOrderAssignmentUpdate(assigned_to_user_id: employee.userId, assigned_to_name: employee.displayName, assigned_by_user_id: manager.id, assigned_by_name: manager.fullName, assigned_at: ISO8601DateFormatter().string(from: Date()), status: status)).eq("custom_order_id", value: String(order.customOrderId)).execute()
        try await writeAudit(orderId: order.customOrderId, action: "ASSIGN_ORDER", fieldName: "assigned_to_user_id", oldValue: order.assignedToUserId.map(String.init), newValue: "\(employee.userId)", reason: employee.displayName, user: manager, device: device)
        if order.status == .new {
            try await writeStatusHistory(orderId: order.customOrderId, oldStatus: order.status, newStatus: .assigned, reason: "Assigned to \(employee.displayName)", user: manager, device: device)
        }
    }

    func updateStatus(order: CustomOrder, status: CustomOrderStatus, reason: String?, user: AppUser, device: TrackedDevice?) async throws {
        _ = try await client.from("custom_orders").update(CustomOrderStatusUpdate(status: status.rawValue, completed_at: status == .completed ? ISO8601DateFormatter().string(from: Date()) : nil)).eq("custom_order_id", value: String(order.customOrderId)).execute()
        if order.status != status {
            try await writeStatusHistory(orderId: order.customOrderId, oldStatus: order.status, newStatus: status, reason: normalized(reason), user: user, device: device)
            try await writeAudit(orderId: order.customOrderId, action: "STATUS_CHANGE", fieldName: "status", oldValue: order.status.rawValue, newValue: status.rawValue, reason: normalized(reason), user: user, device: device)
        }
    }

    func updateLineProduction(order: CustomOrder, line: CustomOrderLine, status: CustomOrderProductionStatus, oldStatus: CustomOrderProductionStatus? = nil, notes: String?, user: AppUser, device: TrackedDevice?) async throws {
        let previousStatus = oldStatus ?? line.productionStatus
        _ = try await client.from("custom_order_lines").update(CustomOrderLineProductionUpdate(production_status: status.rawValue, production_updated_at: ISO8601DateFormatter().string(from: Date()), production_updated_by_user_id: user.id, production_updated_by_name: user.fullName)).eq("custom_order_line_id", value: String(line.customOrderLineId)).execute()
        _ = try await client.from("custom_order_line_production_history").insert(CustomOrderLineProductionHistoryInsert(custom_order_id: order.customOrderId, custom_order_line_id: line.customOrderLineId, custom_item_id: line.customItemId, custom_variant_id: line.variantId, item_name: line.itemName, variant_name: line.variantName, old_status: previousStatus.rawValue, new_status: status.rawValue, notes: normalized(notes), updated_by_user_id: user.id, updated_by_name: user.fullName, device_id: device?.id.uuidString, device_name: device?.deviceName ?? device?.modelName)).execute()
        try await writeAudit(orderId: order.customOrderId, action: "PRODUCTION_UPDATE", fieldName: "production_status", oldValue: previousStatus.rawValue, newValue: status.rawValue, reason: normalized(notes), user: user, device: device)
    }

    func deliverLine(order: CustomOrder, line: CustomOrderLine, notes: String?, user: AppUser, device: TrackedDevice?) async throws {
        _ = try await client.from("custom_order_lines").update(CustomOrderLineDeliveryUpdate(delivery_status: CustomOrderDeliveryStatus.delivered.rawValue, delivered_at: ISO8601DateFormatter().string(from: Date()), delivered_by_user_id: user.id, delivered_by_name: user.fullName)).eq("custom_order_line_id", value: String(line.customOrderLineId)).execute()
        _ = try await client.from("custom_order_line_deliveries").insert(CustomOrderLineDeliveryInsert(custom_order_id: order.customOrderId, custom_order_line_id: line.customOrderLineId, custom_item_id: line.customItemId, custom_variant_id: line.variantId, item_name: line.itemName, variant_name: line.variantName, delivered_by_user_id: user.id, delivered_by_name: user.fullName, delivery_notes: normalized(notes), device_id: device?.id.uuidString, device_name: device?.deviceName ?? device?.modelName)).execute()
        try await writeAudit(orderId: order.customOrderId, action: "DELIVER_LINE", fieldName: "custom_order_line_id", oldValue: "\(line.customOrderLineId)", newValue: CustomOrderDeliveryStatus.delivered.rawValue, reason: normalized(notes), user: user, device: device)
        let allDelivered = order.lines.allSatisfy { $0.customOrderLineId == line.customOrderLineId || $0.deliveryStatus == .delivered || !$0.returns.isEmpty }
        if allDelivered && order.balanceDue <= 0 {
            try await updateStatus(order: order, status: .delivered, reason: "All non-returned lines delivered and balance is zero.", user: user, device: device)
        }
    }

    func refundLine(order: CustomOrder, line: CustomOrderLine, returnType: String, reason: String, amount: Double, notes: String?, user: AppUser, device: TrackedDevice?, store: Store?, hasApprovalPermission: Bool, currentBalanceDue: Double? = nil) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw CustomOrderServiceError.refundReasonRequired }
        guard amount > 0 else { throw CustomOrderServiceError.invalidPaymentAmount }
        let preferences = try await fetchCompanyPreferences(locationId: store?.id ?? order.locationId)
        if preferences.customOrderRefundApprovalLimit > 0 && amount > preferences.customOrderRefundApprovalLimit && !hasApprovalPermission {
            throw CustomOrderServiceError.refundApprovalRequired
        }
        let balanceReduction: Double
        let payoutAmount: Double
        let startingBalance = currentBalanceDue ?? order.balanceDue
        if trimmedReason == "Payment Mistake" {
            balanceReduction = -amount
            payoutAmount = 0
        } else {
            balanceReduction = min(startingBalance, amount)
            payoutAmount = max(amount - balanceReduction, 0)
        }
        let cashDrawer: ResolvedCashDrawer?
        if payoutAmount > 0 {
            guard let store else { throw CashDrawerError.missingStore }
            cashDrawer = try await CashDrawerService().resolveAssignedDrawer(storeId: store.id, deviceId: device?.id)
        } else {
            cashDrawer = nil
        }

        _ = try await client.from("custom_order_line_returns").insert(CustomOrderLineReturnInsert(custom_order_id: order.customOrderId, custom_order_line_id: line.customOrderLineId, custom_item_id: line.customItemId, custom_variant_id: line.variantId, item_name: line.itemName, variant_name: line.variantName, return_type: returnType, restock_action: "NO_RESTOCK", refund_amount: amount, balance_reduction: balanceReduction, payout_amount: payoutAmount, reason: trimmedReason, notes: normalized(notes), cash_drawer_id: cashDrawer?.drawerId, cash_drawer_name: cashDrawer?.drawerName, created_by_user_id: user.id, created_by_name: user.fullName, device_id: device?.id.uuidString, device_name: device?.deviceName ?? device?.modelName)).execute()

        let nextBalance = trimmedReason == "Payment Mistake" ? startingBalance + amount : max(startingBalance - balanceReduction, 0)
        let nextStatus: CustomOrderPaymentStatus = nextBalance <= 0 ? .paid : (nextBalance < order.totalAmount ? .partial : .unpaid)
        _ = try await client
            .from("custom_orders")
            .update(CustomOrderPaymentStatusUpdate(balance_due: nextBalance, payment_status: nextStatus.rawValue))
            .eq("custom_order_id", value: String(order.customOrderId))
            .execute()
        try await writeAudit(orderId: order.customOrderId, action: trimmedReason == "Payment Mistake" ? "PAYMENT_MISTAKE_REFUND" : "LINE_REFUND", fieldName: "balance_due", oldValue: String(format: "%.2f", startingBalance), newValue: String(format: "%.2f", nextBalance), reason: trimmedReason, user: user, device: device)
    }

    func recordPayment(order: CustomOrder, method: CustomOrderPaymentMethod, amount: Double, reference: String?, user: AppUser, store: Store?, device: TrackedDevice?) async throws {
        guard amount > 0 else { throw CustomOrderServiceError.invalidPaymentAmount }
        if method.requiresReference, normalized(reference) == nil { throw CustomOrderServiceError.paymentReferenceRequired }
        let cashDrawer: ResolvedCashDrawer?
        if method == .cash {
            guard let store else { throw CashDrawerError.missingStore }
            cashDrawer = try await CashDrawerService().resolveAssignedDrawer(storeId: store.id, deviceId: device?.id)
        } else {
            cashDrawer = nil
        }

        let paidAmount = min(amount, order.balanceDue)
        let paymentId = try await recordCustomOrderPayment(
            orderId: order.customOrderId,
            amount: paidAmount,
            method: method,
            reference: reference,
            user: user,
            device: device,
            cashDrawer: cashDrawer
        )

        let nextPaid = order.amountPaid + paidAmount
        let nextBalance = max(order.balanceDue - paidAmount, 0)
        let nextStatus: CustomOrderPaymentStatus = nextBalance <= 0 ? .paid : .partial
        _ = try await client
            .from("custom_orders")
            .update(CustomOrderPostPaymentUpdate(amount_paid: nextPaid, balance_due: nextBalance, payment_status: nextStatus.rawValue, payment_method: method.rawValue, payment_reference: normalized(reference)))
            .eq("custom_order_id", value: String(order.customOrderId))
            .execute()

        if method == .account {
            try await chargeCustomOrderBalanceToAccount(customerId: order.customerId, orderId: order.customOrderId, amount: paidAmount, note: "Custom order account charge \(order.displayNumber)", user: user, store: store, device: device)
            try await writeAudit(orderId: order.customOrderId, action: "ACCOUNT_CHARGE", fieldName: "balance_due", oldValue: String(format: "%.2f", order.balanceDue), newValue: String(format: "%.2f", nextBalance), reason: "Post-order account charge", user: user, device: device)
        } else {
            try await recordCustomOrderPaymentLedger(
                customerId: order.customerId,
                orderId: order.customOrderId,
                amount: paidAmount,
                paymentId: paymentId,
                note: "Custom order payment. payment_method=\(method.rawValue), custom_order_id=\(order.customOrderId), order_number=\(order.displayNumber)",
                user: user,
                store: store,
                device: device,
                paymentMethod: method,
                paymentReference: reference,
                cashDrawer: cashDrawer
            )
            try await writeAudit(orderId: order.customOrderId, action: "ADD_PAYMENT", fieldName: "amount_paid", oldValue: String(format: "%.2f", order.amountPaid), newValue: String(format: "%.2f", nextPaid), reason: method.title, user: user, device: device)
        }
    }

    func cancelOrder(order: CustomOrder, reason: String, user: AppUser, device: TrackedDevice?) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else { throw CustomOrderServiceError.cancelReasonRequired }
        _ = try await client
            .from("custom_orders")
            .update(CustomOrderCancelUpdate(status: CustomOrderStatus.cancelled.rawValue, cancellation_reason: trimmedReason, cancelled_at: ISO8601DateFormatter().string(from: Date()), cancelled_by_user_id: user.id, cancelled_by_name: user.fullName))
            .eq("custom_order_id", value: String(order.customOrderId))
            .execute()
        try await writeStatusHistory(orderId: order.customOrderId, oldStatus: order.status, newStatus: .cancelled, reason: trimmedReason, user: user, device: device)
        try await writeAudit(orderId: order.customOrderId, action: "CANCEL_ORDER", fieldName: "status", oldValue: order.status.rawValue, newValue: CustomOrderStatus.cancelled.rawValue, reason: trimmedReason, user: user, device: device)
    }

    func fetchEndOfDay(locationId: Int?, deviceId: String?, userId: Int?, cashDrawerId: Int64?, date: Date = Date()) async throws -> [CustomOrderPayment] {
        let range = Self.dayRange(for: date)
        var query = client
            .from("custom_order_payments")
            .select("custom_order_payment_id, custom_order_id, payment_method, payment_amount, payment_reference, cash_drawer_id, cash_drawer_name, payment_action, created_at, taken_by_user_id, taken_by_name, device_id, device_name, custom_orders!inner(location_id, location_name)")
            .gte("created_at", value: range.start)
            .lt("created_at", value: range.end)

        if let locationId {
            query = query.eq("custom_orders.location_id", value: locationId)
        }
        if let deviceId, !deviceId.isEmpty {
            query = query.eq("device_id", value: deviceId)
        }
        if let userId {
            query = query.eq("taken_by_user_id", value: userId)
        }
        if let cashDrawerId {
            query = query.eq("cash_drawer_id", value: String(cashDrawerId))
        }

        return try await query.order("created_at", ascending: false).execute().value
    }

    func fetchEndOfDaySales(locationId: Int?, deviceId: String?, userId: Int?, cashDrawerId: Int64?, date: Date = Date()) async throws -> [CustomOrderEndOfDaySale] {
        let range = Self.dayRange(for: date)
        var query = client
            .from("custom_orders")
            .select("custom_order_id, order_number, total_amount, amount_paid, balance_due, payment_status, cash_drawer_id, cash_drawer_name, created_at")
            .gte("created_at", value: range.start)
            .lt("created_at", value: range.end)

        if let locationId {
            query = query.eq("location_id", value: locationId)
        }
        if let deviceId, !deviceId.isEmpty {
            query = query.eq("device_id", value: deviceId)
        }
        if let userId {
            query = query.eq("taken_by_user_id", value: userId)
        }
        if let cashDrawerId {
            query = query.eq("cash_drawer_id", value: String(cashDrawerId))
        }

        return try await query.order("created_at", ascending: false).execute().value
    }

    func fetchEndOfDayReturns(locationId: Int?, deviceId: String?, userId: Int?, cashDrawerId: Int64?, date: Date = Date()) async throws -> [CustomOrderEndOfDayReturn] {
        let range = Self.dayRange(for: date)
        var query = client
            .from("custom_order_line_returns")
            .select("custom_order_line_return_id, custom_order_id, custom_order_line_id, item_name, variant_name, refund_amount, balance_reduction, payout_amount, reason, cash_drawer_id, cash_drawer_name, created_by_user_id, created_by_name, device_id, device_name, created_at, custom_orders!inner(location_id, location_name)")
            .gte("created_at", value: range.start)
            .lt("created_at", value: range.end)

        if let locationId {
            query = query.eq("custom_orders.location_id", value: locationId)
        }
        if let deviceId, !deviceId.isEmpty {
            query = query.eq("device_id", value: deviceId)
        }
        if let userId {
            query = query.eq("created_by_user_id", value: userId)
        }
        if let cashDrawerId {
            query = query.eq("cash_drawer_id", value: String(cashDrawerId))
        }

        return try await query.order("created_at", ascending: false).execute().value
    }

    private static func dayRange(for date: Date) -> (start: String, end: String) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date
        let formatter = ISO8601DateFormatter()
        return (formatter.string(from: startOfDay), formatter.string(from: endOfDay))
    }

    private var itemSelection: String {
        """
        custom_item_id,
        item_name,
        sku,
        barcode,
        description,
        product_type,
        pricing_type,
        fixed_price,
        area_price,
        area_price_unit,
        dimension_unit,
        max_width,
        max_length,
        image_url,
        quantity_on_hand,
        reorder_level,
        sold_quantity,
        has_variants,
        is_active,
        created_at,
        updated_at,
        custom_order_item_barcodes(custom_item_barcode_id, custom_item_id, barcode, created_at),
        custom_order_item_variants(custom_variant_id, custom_item_id, variant_name, sku, barcode, fixed_price, quantity_on_hand, reorder_level, sold_quantity, image_url, is_active)
        """
    }

    private var orderSelection: String {
        """
        custom_order_id,
        order_number,
        customer_id,
        customer_name,
        customer_phone,
        status,
        payment_status,
        payment_method,
        payment_reference,
        cash_drawer_id,
        cash_drawer_name,
        due_date,
        order_notes,
        total_amount,
        amount_paid,
        balance_due,
        minimum_deposit_required,
        deposit_override_reason,
        deposit_override_by_user_id,
        deposit_override_by_name,
        location_id,
        location_name,
        device_id,
        device_name,
        taken_by_user_id,
        taken_by_name,
        assigned_to_user_id,
        assigned_to_name,
        assigned_by_user_id,
        assigned_by_name,
        assigned_at,
        completed_at,
        created_at,
        updated_at,
        custom_order_payments(custom_order_payment_id, custom_order_id, payment_method, payment_amount, payment_reference, cash_drawer_id, cash_drawer_name, created_at, taken_by_name),
        custom_order_lines(custom_order_line_id, custom_order_id, custom_item_id, custom_variant_id, item_name, variant_name, pricing_type, unit_price, original_line_total, line_discount_percent, line_discount_amount, line_discount_by_name, line_discount_reason, line_total, original_base_price, price_override_price, price_override_reason, price_override_by_name, width_value, length_value, dimension_unit, area_value, area_unit, area_price, base_item_price, customization_details, order_instructions, delivery_status, delivered_at, delivered_by_name, production_status, production_updated_at, production_updated_by_name, sort_order, created_at, custom_order_line_print_addons(custom_order_line_print_addon_id, print_material_name, print_size_name, pricing_mode, print_description, print_charge, print_line_count), custom_order_line_returns(custom_order_line_return_id, custom_order_line_id, return_type, refund_amount, balance_reduction, payout_amount, reason, created_at, created_by_name))
        """
    }

    @discardableResult
    private func recordCustomOrderPayment(
        orderId: Int64,
        amount: Double,
        method: CustomOrderPaymentMethod,
        reference: String?,
        user: AppUser,
        device: TrackedDevice?,
        cashDrawer: ResolvedCashDrawer?
    ) async throws -> String {
        let inserted: CustomOrderPaymentIdRow = try await client
            .from("custom_order_payments")
            .insert(CustomOrderPaymentInsert(custom_order_id: orderId, payment_amount: amount, payment_method: method.rawValue, payment_reference: normalized(reference), cash_drawer_id: cashDrawer?.drawerId, cash_drawer_name: cashDrawer?.drawerName, taken_by_user_id: user.id, taken_by_name: user.fullName, payment_action: "PAYMENT", device_id: device?.id.uuidString, device_name: device?.deviceName ?? device?.modelName))
            .select("custom_order_payment_id")
            .single()
            .execute()
            .value

        return String(format: "COP-%06lld", inserted.custom_order_payment_id)
    }

    private func recordCustomOrderPaymentLedger(
        customerId: Int,
        orderId: Int64,
        amount: Double,
        paymentId: String,
        note: String?,
        user: AppUser,
        store: Store?,
        device: TrackedDevice?,
        paymentMethod: CustomOrderPaymentMethod,
        paymentReference: String?,
        cashDrawer: ResolvedCashDrawer?
    ) async throws {
        _ = try await client.from("customer_account_transactions").insert(CustomerAccountTransactionInsert(customer_id: customerId, sale_id: nil, amount: amount, transaction_type: "CUSTOM_ORDER_PAID", note: normalized(note), payment_id: paymentId, payment_method: paymentMethod.rawValue, payment_reference: normalized(paymentReference), cash_drawer_id: cashDrawer?.drawerId, cash_drawer_name: cashDrawer?.drawerName, user_name: user.fullName, location_id: store?.id, custom_order_id: orderId, device_id: device?.id.uuidString, device_name: device?.deviceName ?? device?.modelName)).execute()
    }

    private func chargeCustomOrderBalanceToAccount(customerId: Int, orderId: Int64, amount: Double, note: String?, user: AppUser, store: Store?, device: TrackedDevice?) async throws {
        let rows: [ChargeCustomOrderBalanceResult] = try await client
            .rpc(
                "charge_custom_order_balance_to_account",
                params: ChargeCustomOrderBalanceParams(
                    target_customer_id: customerId,
                    target_custom_order_id: orderId,
                    target_amount: amount,
                    target_note: normalized(note),
                    target_user_name: user.fullName,
                    target_location_id: store?.id,
                    target_device_id: device?.id.uuidString,
                    target_device_name: device?.deviceName ?? device?.modelName
                )
            )
            .execute()
            .value

        guard !rows.isEmpty else {
            throw NSError(domain: "CustomOrderService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The custom order balance was not charged to the customer account."
            ])
        }
    }

    private func writeAudit(orderId: Int64, action: String, fieldName: String?, oldValue: String?, newValue: String?, reason: String?, user: AppUser, device: TrackedDevice?) async throws {
        _ = try await client
            .from("custom_order_audit_log")
            .insert(CustomOrderAuditInsert(
                custom_order_id: orderId,
                action_type: action,
                field_name: fieldName,
                old_value: normalized(oldValue),
                new_value: normalized(newValue),
                reason: normalized(reason),
                user_id: user.id,
                user_name: user.fullName,
                device_id: device?.id.uuidString,
                device_name: device?.deviceName ?? device?.modelName
            ))
            .execute()
    }

    private func writeStatusHistory(orderId: Int64, oldStatus: CustomOrderStatus?, newStatus: CustomOrderStatus, reason: String?, user: AppUser, device: TrackedDevice?) async throws {
        _ = try await client
            .from("custom_order_status_history")
            .insert(CustomOrderStatusHistoryInsert(
                custom_order_id: orderId,
                old_status: oldStatus?.rawValue,
                new_status: newStatus.rawValue,
                reason: normalized(reason),
                user_id: user.id,
                user_name: user.fullName,
                device_id: device?.id.uuidString,
                device_name: device?.deviceName ?? device?.modelName
            ))
            .execute()
    }

    private func applySoldQuantity(_ line: CustomOrderDraftLine, user: AppUser) async throws {
        if let variant = line.variant {
            let rows: [CustomOrderVariantQuantityRow] = try await client
                .from("custom_order_item_variants")
                .select("custom_variant_id, quantity_on_hand, sold_quantity")
                .eq("custom_variant_id", value: String(variant.variantId))
                .limit(1)
                .execute()
                .value
            guard let row = rows.first else { return }
            let nextStock = line.item.itemType.deductsStock ? row.quantity_on_hand - line.quantity : row.quantity_on_hand
            _ = try await client
                .from("custom_order_item_variants")
                .update(CustomOrderVariantQuantityUpdate(quantity_on_hand: nextStock, sold_quantity: row.sold_quantity + line.quantity))
                .eq("custom_variant_id", value: String(variant.variantId))
                .execute()
            _ = try await client
                .from("custom_order_item_movements")
                .insert(CustomOrderItemMovementInsert(custom_item_id: line.item.customItemId, change_qty: line.item.itemType.deductsStock ? -line.quantity : 0, reason: "CUSTOM_ORDER_SOLD", note: "sold_by_user_id=\(user.id)", user_name: user.fullName, receive_id: "", receive_device_id: "", receive_sequence: 0, custom_variant_id: variant.variantId, variant_name: variant.variantName))
                .execute()
            return
        }

        let rows: [CustomOrderItemQuantityRow] = try await client
            .from("custom_order_items")
            .select("custom_item_id, quantity_on_hand, sold_quantity")
            .eq("custom_item_id", value: String(line.item.customItemId))
            .limit(1)
            .execute()
            .value
        guard let row = rows.first else { return }
        let nextStock = line.item.itemType.deductsStock ? row.quantity_on_hand - line.quantity : row.quantity_on_hand
        _ = try await client
            .from("custom_order_items")
            .update(CustomOrderItemSoldQuantityUpdate(quantity_on_hand: nextStock, sold_quantity: row.sold_quantity + line.quantity))
            .eq("custom_item_id", value: String(line.item.customItemId))
            .execute()
        _ = try await client
            .from("custom_order_item_movements")
            .insert(CustomOrderItemMovementInsert(custom_item_id: line.item.customItemId, change_qty: line.item.itemType.deductsStock ? -line.quantity : 0, reason: "CUSTOM_ORDER_SOLD", note: "sold_by_user_id=\(user.id)", user_name: user.fullName, receive_id: "", receive_device_id: "", receive_sequence: 0, custom_variant_id: nil, variant_name: nil))
            .execute()
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func orderNumberMilliseconds() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000).rounded(.down))
    }

    private static func orderNumber(milliseconds: Int64) -> String {
        "CO-\(milliseconds)"
    }

    private static func isDuplicateOrderNumberError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return (message.contains("23505") || message.contains("duplicate"))
            && (message.contains("order_number") || message.contains("custom_orders"))
    }
}

enum ReceivingLookupItem {
    case product(ScannedProduct)
    case customItem(CustomOrderItem)
    case customVariant(item: CustomOrderItem, variant: CustomOrderItemVariant)
}

struct CustomOrderItemSelectionResult {
    let item: CustomOrderItem?
    let variant: CustomOrderItemVariant?
}

struct ReceiveCustomOrderItem {
    let customItemId: Int64
    var customVariantId: Int64? = nil
    var variantName: String? = nil
    let itemName: String
    let quantity: Int
}

struct CustomOrderCreateResult {
    let orderId: Int64
    let totalAmount: Double
}

enum CustomOrderServiceError: LocalizedError {
    case missingItemName
    case missingVariantName
    case invalidFixedPrice
    case invalidAreaPrice
    case invalidVariantPrice
    case missingPrintMaterialName
    case missingPrintPresetName
    case invalidPrintPresetPrice
    case customItemNotFound
    case orderNeedsLine
    case customerNeedsNameAndPhone
    case variablePriceRequired
    case priceOverrideReasonRequired
    case discountReasonRequired
    case paymentReferenceRequired
    case depositOverrideReasonRequired
    case refundReasonRequired
    case refundApprovalRequired
    case invalidPaymentAmount
    case cancelReasonRequired
    case orderNumberGenerationFailed(String?)

    var errorDescription: String? {
        switch self {
        case .missingItemName: return "Enter an item name."
        case .missingVariantName: return "Enter a variant name."
        case .invalidFixedPrice: return "Fixed pricing items need a valid fixed price."
        case .invalidAreaPrice: return "Area pricing items need a valid area price."
        case .invalidVariantPrice: return "This variant needs a valid price."
        case .missingPrintMaterialName: return "Enter a print material name."
        case .missingPrintPresetName: return "Enter a print size name."
        case .invalidPrintPresetPrice: return "Enter a valid print size price."
        case .customItemNotFound: return "Custom order item not found."
        case .orderNeedsLine: return "Add at least one line to the custom order."
        case .customerNeedsNameAndPhone: return "Custom orders require customer name and phone."
        case .variablePriceRequired: return "Manual and area pricing need a valid entered price."
        case .priceOverrideReasonRequired: return "Manual or area prices require a price override reason."
        case .discountReasonRequired: return "Line discount reason is required."
        case .paymentReferenceRequired: return "Card, cheque, and MMG payments require a reference."
        case .depositOverrideReasonRequired: return "A deposit override reason is required when payment is below the minimum deposit."
        case .refundReasonRequired: return "Select a refund or return reason."
        case .refundApprovalRequired: return "This refund is above the approval limit and needs refund approval permission."
        case .invalidPaymentAmount: return "Enter a valid amount greater than zero."
        case .cancelReasonRequired: return "Cancellation reason is required."
        case .orderNumberGenerationFailed: return "Could not generate a unique custom order number. Please try saving the order again."
        }
    }
}

private struct CompanyCustomizationUpsert: Encodable {
    let location_id: Int?
    let company_name: String
    let receipt_logo_url: String
    let receipt_header_line: String
    let receipt_footer_line: String
    let show_receipt_logo: Bool
    let show_sale_id_on_receipt: Bool
    let show_device_id_on_receipt: Bool
    let show_customer_on_receipt: Bool
    let show_sku_on_receipt: Bool
    let show_item_discounts_on_receipt: Bool
    let show_payment_status_on_receipt: Bool
    let next_receipt_counter: Int
    let custom_order_slip_enabled: Bool
    let custom_order_slip_auto_print: Bool
    let custom_order_slip_title: String
    let custom_order_slip_contact_line: String
    let custom_order_slip_email_line: String
    let custom_order_slip_footer_note: String
    let custom_order_slip_blank_detail_lines: Int
    let custom_order_slip_show_logo: Bool
    let custom_order_slip_show_order_number: Bool
    let custom_order_slip_show_due_date: Bool
    let custom_order_slip_show_customer_phone: Bool
    let custom_order_slip_show_customer_account: Bool
    let custom_order_slip_show_store: Bool
    let custom_order_slip_show_device: Bool
    let custom_order_slip_show_cashier: Bool
    let custom_order_slip_show_line_items: Bool
    let custom_order_slip_show_pricing: Bool
    let custom_order_slip_show_payment_summary: Bool
    let custom_order_slip_show_payment_reference: Bool
    let custom_order_slip_show_taken_by: Bool
    let custom_order_slip_show_signatures: Bool
    let custom_order_minimum_deposit_percent: Double
    let custom_order_refund_approval_limit: Double
}

private struct CustomOrderItemUpsert: Encodable {
    let item_name: String
    let barcode: String?
    let description: String?
    let product_type: String
    let pricing_type: String
    let fixed_price: Double?
    let area_price: Double?
    let area_price_unit: String?
    let dimension_unit: String?
    let max_width: Double?
    let max_length: Double?
    let image_url: String?
    let quantity_on_hand: Double
    let reorder_level: Double
    let has_variants: Bool
    let is_active: Bool
}

private struct CustomOrderVariantUpsert: Encodable {
    let custom_item_id: Int64
    let variant_name: String
    let barcode: String?
    let fixed_price: Double?
    let quantity_on_hand: Double
    let reorder_level: Double
    let image_url: String?
    let is_active: Bool
}

private struct CustomOrderItemHasVariantsUpdate: Encodable {
    let has_variants: Bool
}

struct CustomOrderItemSaveResult: Decodable {
    let custom_item_id: Int64
    let sku: String?
}

struct CustomOrderVariantSaveResult: Decodable {
    let custom_variant_id: Int64
    let sku: String?
}

private struct CustomOrderItemBarcodeInsert: Encodable { let custom_item_id: Int64; let barcode: String }
private struct CustomOrderItemActiveUpdate: Encodable { let is_active: Bool }
private struct CustomOrderItemBarcodeLookup: Decodable { let custom_item_id: Int64 }
private struct CustomOrderVariantLookupRow: Decodable { let custom_item_id: Int64; let custom_variant_id: Int64 }
private struct CustomOrderQuantityRow: Decodable { let custom_item_id: Int64; let quantity_on_hand: Double }
private struct CustomOrderQuantityUpdate: Encodable { let quantity_on_hand: Double }
private struct CustomOrderVariantReceiveQuantityRow: Decodable {
    let custom_variant_id: Int64
    let custom_item_id: Int64
    let variant_name: String
    let quantity_on_hand: Double
}

private struct CustomOrderPrintMaterialUpsert: Encodable {
    let material_name: String
    let description: String?
    let pricing_mode: String
    let is_active: Bool
}

private struct CustomOrderPrintSizePresetUpsert: Encodable {
    let print_material_id: Int64
    let preset_name: String
    let fixed_price: Double
    let pricing_mode: String
    let is_active: Bool
}

private struct CustomOrderPrintMaterialIdRow: Decodable { let print_material_id: Int64 }
private struct CustomOrderPrintSizePresetIdRow: Decodable { let print_size_preset_id: Int64 }

private struct CustomOrderItemMovementInsert: Encodable {
    let custom_item_id: Int64
    let change_qty: Double
    let reason: String
    let note: String?
    let user_name: String
    let receive_id: String
    let receive_device_id: String
    let receive_sequence: Int
    var custom_variant_id: Int64? = nil
    var variant_name: String? = nil
}

private struct CustomOrderItemQuantityRow: Decodable {
    let custom_item_id: Int64
    let quantity_on_hand: Double
    let sold_quantity: Double
}

private struct CustomOrderVariantQuantityRow: Decodable {
    let custom_variant_id: Int64
    let quantity_on_hand: Double
    let sold_quantity: Double
}

private struct CustomOrderItemSoldQuantityUpdate: Encodable {
    let quantity_on_hand: Double
    let sold_quantity: Double
}

private struct CustomOrderVariantQuantityUpdate: Encodable {
    let quantity_on_hand: Double
    let sold_quantity: Double
}

private struct CustomOrderCustomerInsert: Encodable {
    let name: String
    let phone: String
    let email: String?
    let customer_type_id: Int
    let is_active: Bool
    let is_business: Bool
}

private struct CustomOrderInsert: Encodable {
    let order_number: String
    let customer_id: Int
    let customer_name: String
    let customer_phone: String
    let status: String
    let due_date: String?
    let order_notes: String?
    let total_amount: Double
    let payment_method: String?
    let payment_reference: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let payment_status: String
    let amount_paid: Double
    let balance_due: Double
    let minimum_deposit_required: Double
    let deposit_override_reason: String?
    let deposit_override_by_user_id: Int?
    let deposit_override_by_name: String?
    let location_id: Int?
    let location_name: String?
    let device_id: String?
    let device_name: String?
    let taken_by_user_id: Int
    let taken_by_name: String
}

private struct CustomOrderIdRow: Decodable {
    let custom_order_id: Int64
    let order_number: String
}
private struct CustomOrderLineIdRow: Decodable { let custom_order_line_id: Int64 }
private struct CustomOrderPaymentIdRow: Decodable { let custom_order_payment_id: Int64 }

private struct CustomOrderLineInsertSeed {
    let line: CustomOrderDraftLine
    let unitPrice: Double
    let sortOrder: Int
}

private struct CustomOrderLineInsert: Encodable {
    let custom_order_id: Int64
    let custom_item_id: Int64
    let custom_variant_id: Int64?
    let item_name: String
    let variant_name: String?
    let pricing_type: String
    let unit_price: Double
    let line_total: Double
    let customization_details: String
    let order_instructions: String?
    let sort_order: Int
    let width_value: Double?
    let length_value: Double?
    let dimension_unit: String?
    let area_value: Double?
    let area_unit: String?
    let area_price: Double?
    let base_item_price: Double?
    let original_line_total: Double
    let line_discount_percent: Double
    let line_discount_amount: Double
    let line_discount_by_user_id: Int?
    let line_discount_by_name: String?
    let line_discount_reason: String?
    let original_base_price: Double?
    let price_override_price: Double?
    let price_override_reason: String?
    let price_override_by_user_id: Int?
    let price_override_by_name: String?
    let minimum_deposit_percent: Double

    init(orderId: Int64, seed: CustomOrderLineInsertSeed, user: AppUser) {
        let line = seed.line
        custom_order_id = orderId
        custom_item_id = line.item.customItemId
        custom_variant_id = line.variant?.variantId
        item_name = line.item.itemName
        variant_name = line.variant?.variantName
        pricing_type = line.item.pricingType.rawValue
        unit_price = seed.unitPrice
        line_total = line.lineTotal
        customization_details = line.customizationDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        order_instructions = line.lineNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : line.lineNotes
        sort_order = seed.sortOrder
        width_value = line.widthValue
        length_value = line.lengthValue
        dimension_unit = line.item.pricingType == .area ? line.dimensionUnit : nil
        area_value = line.areaValue
        area_unit = line.item.pricingType == .area ? line.areaUnit : nil
        area_price = line.item.pricingType == .area ? line.areaPrice : nil
        base_item_price = line.basePrice
        original_line_total = line.originalLineTotal
        line_discount_percent = line.discountPercent
        line_discount_amount = line.discountAmount
        line_discount_by_user_id = line.discountPercent > 0 ? user.id : nil
        line_discount_by_name = line.discountPercent > 0 ? user.fullName : nil
        line_discount_reason = line.discountPercent > 0 ? line.discountReason : nil
        original_base_price = line.basePrice
        price_override_price = line.hasPriceOverride ? seed.unitPrice : nil
        price_override_reason = line.hasPriceOverride ? line.priceOverrideReason : nil
        price_override_by_user_id = line.hasPriceOverride ? user.id : nil
        price_override_by_name = line.hasPriceOverride ? user.fullName : nil
        minimum_deposit_percent = 0
    }
}

private struct CustomOrderLinePrintAddonInsert: Encodable {
    let custom_order_line_id: Int64
    let print_material_id: Int64?
    let print_material_name: String
    let print_size_preset_id: Int64?
    let print_size_name: String?
    let pricing_mode: String
    let print_charge: Double
    let print_line_count: Int
    let sort_order: Int
    let print_description: String?
}

private struct CustomOrderPaymentInsert: Encodable {
    let custom_order_id: Int64
    let payment_amount: Double
    let payment_method: String
    let payment_reference: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let taken_by_user_id: Int
    let taken_by_name: String
    let payment_action: String
    let device_id: String?
    let device_name: String?
}

private struct CustomerAccountTransactionInsert: Encodable {
    let customer_id: Int
    let sale_id: Int?
    let amount: Double
    let transaction_type: String
    let note: String?
    let payment_id: String?
    let payment_method: String?
    let payment_reference: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let user_name: String
    let location_id: Int?
    let custom_order_id: Int64
    let device_id: String?
    let device_name: String?
}

private struct ChargeCustomOrderBalanceParams: Encodable {
    let target_customer_id: Int
    let target_custom_order_id: Int64
    let target_amount: Double
    let target_note: String?
    let target_user_name: String
    let target_location_id: Int?
    let target_device_id: String?
    let target_device_name: String?
}

private struct ChargeCustomOrderBalanceResult: Decodable {
    let account_transaction_id: Int
    let new_balance: Double
}

private struct CustomOrderAssignmentUpdate: Encodable {
    let assigned_to_user_id: Int
    let assigned_to_name: String
    let assigned_by_user_id: Int
    let assigned_by_name: String
    let assigned_at: String
    let status: String
}

private struct CustomOrderStatusUpdate: Encodable {
    let status: String
    let completed_at: String?
}

private struct CustomOrderPaymentStatusUpdate: Encodable {
    let balance_due: Double
    let payment_status: String
}

private struct CustomOrderPostPaymentUpdate: Encodable {
    let amount_paid: Double
    let balance_due: Double
    let payment_status: String
    let payment_method: String
    let payment_reference: String?
}

private struct CustomOrderCancelUpdate: Encodable {
    let status: String
    let cancellation_reason: String
    let cancelled_at: String
    let cancelled_by_user_id: Int
    let cancelled_by_name: String
}

private struct CustomOrderAuditInsert: Encodable {
    let custom_order_id: Int64
    let action_type: String
    let field_name: String?
    let old_value: String?
    let new_value: String?
    let reason: String?
    let user_id: Int
    let user_name: String
    let device_id: String?
    let device_name: String?
}

private struct CustomOrderStatusHistoryInsert: Encodable {
    let custom_order_id: Int64
    let old_status: String?
    let new_status: String
    let reason: String?
    let user_id: Int
    let user_name: String
    let device_id: String?
    let device_name: String?
}

private struct CustomOrderLineProductionUpdate: Encodable {
    let production_status: String
    let production_updated_at: String
    let production_updated_by_user_id: Int
    let production_updated_by_name: String
}

private struct CustomOrderLineProductionHistoryInsert: Encodable {
    let custom_order_id: Int64
    let custom_order_line_id: Int64
    let custom_item_id: Int64
    let custom_variant_id: Int64?
    let item_name: String
    let variant_name: String?
    let old_status: String
    let new_status: String
    let notes: String?
    let updated_by_user_id: Int
    let updated_by_name: String
    let device_id: String?
    let device_name: String?
}

private struct CustomOrderLineDeliveryUpdate: Encodable {
    let delivery_status: String
    let delivered_at: String
    let delivered_by_user_id: Int
    let delivered_by_name: String
}

private struct CustomOrderLineDeliveryInsert: Encodable {
    let custom_order_id: Int64
    let custom_order_line_id: Int64
    let custom_item_id: Int64
    let custom_variant_id: Int64?
    let item_name: String
    let variant_name: String?
    let delivered_by_user_id: Int
    let delivered_by_name: String
    let delivery_notes: String?
    let device_id: String?
    let device_name: String?
}

private struct CustomOrderLineReturnInsert: Encodable {
    let custom_order_id: Int64
    let custom_order_line_id: Int64
    let custom_item_id: Int64
    let custom_variant_id: Int64?
    let item_name: String
    let variant_name: String?
    let return_type: String
    let restock_action: String
    let refund_amount: Double
    let balance_reduction: Double
    let payout_amount: Double
    let reason: String
    let notes: String?
    let cash_drawer_id: Int64?
    let cash_drawer_name: String?
    let created_by_user_id: Int
    let created_by_name: String
    let device_id: String?
    let device_name: String?
}
