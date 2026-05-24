//
//  CustomOrderModels.swift
//  SmartStock
//

import Foundation

enum CustomOrderPricingType: String, CaseIterable, Identifiable, Codable {
    case fixed = "FIXED"
    case variable = "VARIABLE"
    case area = "AREA"

    var id: String { rawValue }

    var title: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum CustomOrderItemType: String, CaseIterable, Identifiable, Codable {
    case inventory = "INVENTORY"
    case service = "SERVICE"
    case nonInventory = "NON_INVENTORY"

    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
    var deductsStock: Bool { self == .inventory }
}

enum CustomOrderPaymentMethod: String, CaseIterable, Identifiable, Codable {
    case cash = "CASH"
    case card = "CARD"
    case cheque = "CHEQUE"
    case account = "ACCOUNT"
    case mmg = "MMG"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var requiresReference: Bool { self == .card || self == .cheque || self == .mmg }
}

enum CustomOrderPaymentStatus: String, CaseIterable, Identifiable, Codable {
    case unpaid = "UNPAID"
    case partial = "PARTIAL"
    case paid = "PAID"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CustomOrderStatus: String, CaseIterable, Identifiable, Codable {
    case new = "NEW"
    case assigned = "ASSIGNED"
    case inProgress = "IN_PROGRESS"
    case ready = "READY"
    case delivered = "DELIVERED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"

    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

enum CustomOrderDeliveryStatus: String, CaseIterable, Identifiable, Codable {
    case pending = "PENDING"
    case delivered = "DELIVERED"
    case returned = "RETURNED"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum CustomOrderProductionStatus: String, CaseIterable, Identifiable, Codable {
    case notStarted = "NOT_STARTED"
    case designApproved = "DESIGN_APPROVED"
    case printed = "PRINTED"
    case finished = "FINISHED"
    case qualityChecked = "QUALITY_CHECKED"
    case ready = "READY"

    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
}

struct CustomOrderItem: Decodable, Identifiable, Hashable {
    let customItemId: Int64
    let itemName: String
    let sku: String?
    let barcode: String?
    let description: String?
    let itemType: CustomOrderItemType
    let pricingType: CustomOrderPricingType
    let fixedPrice: Double?
    let areaPrice: Double?
    let areaPriceUnit: String?
    let dimensionUnit: String?
    let maxWidth: Double?
    let maxLength: Double?
    let imageUrl: String?
    let quantityOnHand: Double
    let reorderLevel: Double
    let soldQuantity: Double
    let hasVariantsFlag: Bool
    let isActive: Bool
    let createdAt: String?
    let updatedAt: String?
    let variants: [CustomOrderItemVariant]
    let extraBarcodeRows: [CustomOrderItemBarcode]
    let extraBarcodes: [String]

    var id: Int64 { customItemId }
    var code: String { "CUSTOM-\(customItemId)" }
    var displaySku: String { sku?.isEmpty == false ? sku! : code }
    var hasVariants: Bool { hasVariantsFlag || !variants.isEmpty }
    var displayImageUrl: String? { hasVariants ? nil : imageUrl }

    var priceText: String {
        if hasVariants { return "Variants" }
        switch pricingType {
        case .fixed: return String(format: "$%.2f", fixedPrice ?? 0)
        case .variable: return "Variable"
        case .area: return "Area"
        }
    }

    var quantityText: String {
        Self.quantityFormatter.string(from: NSNumber(value: quantityOnHand)) ?? "\(quantityOnHand)"
    }

    enum CodingKeys: String, CodingKey {
        case customItemId = "custom_item_id"
        case itemName = "item_name"
        case sku
        case barcode
        case description
        case itemType = "product_type"
        case pricingType = "pricing_type"
        case fixedPrice = "fixed_price"
        case areaPrice = "area_price"
        case areaPriceUnit = "area_price_unit"
        case dimensionUnit = "dimension_unit"
        case maxWidth = "max_width"
        case maxLength = "max_length"
        case imageUrl = "image_url"
        case quantityOnHand = "quantity_on_hand"
        case reorderLevel = "reorder_level"
        case soldQuantity = "sold_quantity"
        case hasVariantsFlag = "has_variants"
        case isActive = "is_active"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case customOrderItemBarcodes = "custom_order_item_barcodes"
        case customOrderItemVariants = "custom_order_item_variants"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customItemId = try container.decodeCustomFlexibleInt64(forKey: .customItemId)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? "Unnamed Custom Item"
        sku = try container.decodeCustomFlexibleStringIfPresent(forKey: .sku)
        barcode = try container.decodeCustomFlexibleStringIfPresent(forKey: .barcode)
        description = try container.decodeCustomFlexibleStringIfPresent(forKey: .description)
        itemType = CustomOrderItemType(rawValue: (try container.decodeIfPresent(String.self, forKey: .itemType) ?? "INVENTORY").uppercased()) ?? .inventory
        pricingType = CustomOrderPricingType(rawValue: (try container.decodeIfPresent(String.self, forKey: .pricingType) ?? "VARIABLE").uppercased()) ?? .variable
        fixedPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .fixedPrice)
        areaPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .areaPrice)
        areaPriceUnit = try container.decodeCustomFlexibleStringIfPresent(forKey: .areaPriceUnit)
        dimensionUnit = try container.decodeCustomFlexibleStringIfPresent(forKey: .dimensionUnit)
        maxWidth = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .maxWidth)
        maxLength = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .maxLength)
        imageUrl = try container.decodeCustomFlexibleStringIfPresent(forKey: .imageUrl)
        quantityOnHand = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .quantityOnHand) ?? 0
        reorderLevel = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .reorderLevel) ?? 0
        soldQuantity = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .soldQuantity) ?? 0
        hasVariantsFlag = try container.decodeCustomFlexibleBoolIfPresent(forKey: .hasVariantsFlag) ?? false
        isActive = try container.decodeCustomFlexibleBoolIfPresent(forKey: .isActive) ?? true
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
        updatedAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .updatedAt)
        variants = (try? container.decodeIfPresent([CustomOrderItemVariant].self, forKey: .customOrderItemVariants)) ?? []
        extraBarcodeRows = (try? container.decodeIfPresent([CustomOrderItemBarcode].self, forKey: .customOrderItemBarcodes)) ?? []
        extraBarcodes = extraBarcodeRows.map(\.barcode)
    }

    private static let quantityFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

struct CustomOrderItemVariant: Decodable, Identifiable, Hashable {
    let variantId: Int64
    let customItemId: Int64?
    let variantName: String
    let sku: String?
    let barcode: String?
    let price: Double?
    let quantityOnHand: Double
    let reorderLevel: Double
    let soldQuantity: Double
    let imageUrl: String?
    let isActive: Bool

    var id: Int64 { variantId }
    var displaySku: String { sku ?? "VARIANT-\(variantId)" }
    var priceText: String { price.map { String(format: "$%.2f", $0) } ?? "No price" }

    enum CodingKeys: String, CodingKey {
        case variantId = "custom_variant_id"
        case customItemId = "custom_item_id"
        case variantName = "variant_name"
        case sku
        case barcode
        case price = "fixed_price"
        case quantityOnHand = "quantity_on_hand"
        case reorderLevel = "reorder_level"
        case soldQuantity = "sold_quantity"
        case imageUrl = "image_url"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        variantId = try container.decodeCustomFlexibleInt64(forKey: .variantId)
        customItemId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .customItemId)
        variantName = try container.decodeIfPresent(String.self, forKey: .variantName) ?? "Variant"
        sku = try container.decodeCustomFlexibleStringIfPresent(forKey: .sku)
        barcode = try container.decodeCustomFlexibleStringIfPresent(forKey: .barcode)
        price = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .price)
        quantityOnHand = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .quantityOnHand) ?? 0
        reorderLevel = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .reorderLevel) ?? 0
        soldQuantity = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .soldQuantity) ?? 0
        imageUrl = try container.decodeCustomFlexibleStringIfPresent(forKey: .imageUrl)
        isActive = try container.decodeCustomFlexibleBoolIfPresent(forKey: .isActive) ?? true
    }
}

struct CustomOrderItemMovement: Decodable, Identifiable, Hashable {
    let movementId: Int64
    let customItemId: Int64
    let variantId: Int64?
    let variantName: String?
    let changeQuantity: Double
    let reason: String
    let note: String?
    let userName: String?
    let receiveId: String?
    let receiveDeviceId: String?
    let receiveSequence: Int?
    let createdAt: String?

    var id: Int64 { movementId }
    var reasonTitle: String {
        switch reason.uppercased() {
        case "INVENTORY_ENTRY": return "Receiving"
        case "CUSTOM_ORDER_SOLD": return "Custom Order Sale"
        default: return reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
    var isReceiving: Bool { reason.uppercased() == "INVENTORY_ENTRY" }
    var isSale: Bool { reason.uppercased() == "CUSTOM_ORDER_SOLD" }
    var quantityText: String {
        let prefix = changeQuantity > 0 ? "+" : ""
        let value = changeQuantity.rounded() == changeQuantity ? String(Int(changeQuantity)) : String(format: "%.2f", changeQuantity)
        return "\(prefix)\(value)"
    }

    enum CodingKeys: String, CodingKey {
        case movementId = "movement_id"
        case customItemId = "custom_item_id"
        case variantId = "custom_variant_id"
        case variantName = "variant_name"
        case changeQuantity = "change_qty"
        case reason
        case note
        case userName = "user_name"
        case receiveId = "receive_id"
        case receiveDeviceId = "receive_device_id"
        case receiveSequence = "receive_sequence"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        movementId = try container.decodeCustomFlexibleInt64(forKey: .movementId)
        customItemId = try container.decodeCustomFlexibleInt64(forKey: .customItemId)
        variantId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .variantId)
        variantName = try container.decodeCustomFlexibleStringIfPresent(forKey: .variantName)
        changeQuantity = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .changeQuantity) ?? 0
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "MOVEMENT"
        note = try container.decodeCustomFlexibleStringIfPresent(forKey: .note)
        userName = try container.decodeCustomFlexibleStringIfPresent(forKey: .userName)
        receiveId = try container.decodeCustomFlexibleStringIfPresent(forKey: .receiveId)
        receiveDeviceId = try container.decodeCustomFlexibleStringIfPresent(forKey: .receiveDeviceId)
        receiveSequence = try container.decodeCustomFlexibleIntIfPresent(forKey: .receiveSequence)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
    }
}

struct CustomOrderItemBarcode: Decodable, Identifiable, Hashable {
    let customItemBarcodeId: Int64
    let customItemId: Int64?
    let barcode: String
    let createdAt: String?

    var id: Int64 { customItemBarcodeId }

    enum CodingKeys: String, CodingKey {
        case customItemBarcodeId = "custom_item_barcode_id"
        case customItemId = "custom_item_id"
        case barcode
        case createdAt = "created_at"
    }
}

struct CustomOrderPrintMaterial: Decodable, Identifiable, Hashable {
    let materialId: Int64
    let materialName: String
    let description: String?
    let pricingMode: String?
    let isActive: Bool

    var id: Int64 { materialId }
    var pricingModeTitle: String { pricingMode == "PER_LINE" ? "Per Line" : "Fixed Preset" }

    enum CodingKeys: String, CodingKey {
        case materialId = "print_material_id"
        case materialName = "material_name"
        case description
        case pricingMode = "pricing_mode"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        materialId = try container.decodeCustomFlexibleInt64(forKey: .materialId)
        materialName = try container.decodeIfPresent(String.self, forKey: .materialName) ?? "Print Material"
        description = try container.decodeCustomFlexibleStringIfPresent(forKey: .description)
        pricingMode = try container.decodeCustomFlexibleStringIfPresent(forKey: .pricingMode)
        isActive = try container.decodeCustomFlexibleBoolIfPresent(forKey: .isActive) ?? true
    }
}

struct CustomOrderPrintSizePreset: Decodable, Identifiable, Hashable {
    let presetId: Int64
    let materialId: Int64?
    let presetName: String
    let fixedPrice: Double?
    let pricingMode: String?
    let isActive: Bool

    var id: Int64 { presetId }
    var priceText: String {
        if let fixedPrice { return String(format: "$%.2f", fixedPrice) }
        return pricingMode == "PER_LINE" ? "Per line" : "No price"
    }

    enum CodingKeys: String, CodingKey {
        case presetId = "print_size_preset_id"
        case materialId = "print_material_id"
        case presetName = "preset_name"
        case fixedPrice = "fixed_price"
        case pricingMode = "pricing_mode"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        presetId = try container.decodeCustomFlexibleInt64(forKey: .presetId)
        materialId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .materialId)
        presetName = try container.decodeIfPresent(String.self, forKey: .presetName) ?? "Preset"
        fixedPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .fixedPrice)
        pricingMode = try container.decodeCustomFlexibleStringIfPresent(forKey: .pricingMode)
        isActive = try container.decodeCustomFlexibleBoolIfPresent(forKey: .isActive) ?? true
    }
}

struct CustomOrderPrintMaterialDraft {
    var materialName = ""
    var description = ""
    var pricingMode = "FIXED_PRESET"
    var isActive = true

    nonisolated init() {}

    nonisolated init(material: CustomOrderPrintMaterial) {
        materialName = material.materialName
        description = material.description ?? ""
        pricingMode = material.pricingMode ?? "FIXED_PRESET"
        isActive = material.isActive
    }
}

struct CustomOrderPrintSizePresetDraft {
    var presetName = ""
    var fixedPrice = ""
    var pricingMode = "FIXED_PRESET"
    var isActive = true

    nonisolated init() {}

    nonisolated init(preset: CustomOrderPrintSizePreset) {
        presetName = preset.presetName
        fixedPrice = preset.fixedPrice.map { String(format: "%.2f", $0) } ?? ""
        pricingMode = preset.pricingMode ?? "FIXED_PRESET"
        isActive = preset.isActive
    }
}

struct CustomOrderDesignPlacement: Decodable, Identifiable, Hashable {
    let designPlacementId: Int64
    let placementName: String
    let sortOrder: Int
    let isActive: Bool

    var id: Int64 { designPlacementId }

    enum CodingKeys: String, CodingKey {
        case designPlacementId = "design_placement_id"
        case placementName = "placement_name"
        case sortOrder = "sort_order"
        case isActive = "is_active"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        designPlacementId = try container.decodeCustomFlexibleInt64(forKey: .designPlacementId)
        placementName = try container.decodeIfPresent(String.self, forKey: .placementName) ?? "Placement"
        sortOrder = try container.decodeCustomFlexibleIntIfPresent(forKey: .sortOrder) ?? 0
        isActive = try container.decodeCustomFlexibleBoolIfPresent(forKey: .isActive) ?? true
    }
}

struct CustomOrderLinePrintAddon: Decodable, Identifiable {
    let linePrintAddonId: Int64
    let materialName: String?
    let presetName: String?
    let pricingMode: String?
    let printDescription: String?
    let price: Double
    let lineCount: Int

    var id: Int64 { linePrintAddonId }
    var priceText: String { String(format: "$%.2f", price) }

    enum CodingKeys: String, CodingKey {
        case linePrintAddonId = "custom_order_line_print_addon_id"
        case materialName = "print_material_name"
        case presetName = "print_size_name"
        case pricingMode = "pricing_mode"
        case printDescription = "print_description"
        case price = "print_charge"
        case lineCount = "print_line_count"
    }
}

struct CustomOrderPayment: Decodable, Identifiable {
    let paymentId: Int64
    let customOrderId: Int64?
    let paymentMethod: CustomOrderPaymentMethod
    let amount: Double
    let paymentReference: String?
    let cashDrawerId: Int64?
    let cashDrawerName: String?
    let paymentAction: String?
    let createdAt: String?
    let takenByName: String?
    let deviceId: String?
    let deviceName: String?

    var id: Int64 { paymentId }
    var amountText: String { String(format: "$%.2f", amount) }
    var isRefundAction: Bool { paymentAction == "REFUND" || paymentAction == "REVERSAL" }

    enum CodingKeys: String, CodingKey {
        case paymentId = "custom_order_payment_id"
        case customOrderId = "custom_order_id"
        case paymentMethod = "payment_method"
        case amount = "payment_amount"
        case paymentReference = "payment_reference"
        case cashDrawerId = "cash_drawer_id"
        case cashDrawerName = "cash_drawer_name"
        case paymentAction = "payment_action"
        case createdAt = "created_at"
        case takenByName = "taken_by_name"
        case deviceId = "device_id"
        case deviceName = "device_name"
    }
}

struct CustomOrderEndOfDayReturn: Decodable, Identifiable {
    let returnId: Int64
    let customOrderId: Int64?
    let lineId: Int64?
    let itemName: String
    let variantName: String?
    let refundAmount: Double
    let balanceReduction: Double
    let payoutAmount: Double
    let reason: String
    let cashDrawerId: Int64?
    let cashDrawerName: String?
    let createdByName: String?
    let deviceId: String?
    let deviceName: String?
    let createdAt: String?

    var id: Int64 { returnId }
    var amountText: String { String(format: "$%.2f", refundAmount) }
    var payoutText: String { String(format: "$%.2f", payoutAmount) }
    var balanceReductionText: String { String(format: "$%.2f", balanceReduction) }
    var displayName: String { variantName?.isEmpty == false ? "\(itemName) - \(variantName!)" : itemName }

    enum CodingKeys: String, CodingKey {
        case returnId = "custom_order_line_return_id"
        case customOrderId = "custom_order_id"
        case lineId = "custom_order_line_id"
        case itemName = "item_name"
        case variantName = "variant_name"
        case refundAmount = "refund_amount"
        case balanceReduction = "balance_reduction"
        case payoutAmount = "payout_amount"
        case reason
        case cashDrawerId = "cash_drawer_id"
        case cashDrawerName = "cash_drawer_name"
        case createdByName = "created_by_name"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case createdAt = "created_at"
    }
}

struct CustomOrderEndOfDaySale: Decodable, Identifiable {
    let customOrderId: Int64
    let orderNumber: String?
    let totalAmount: Double
    let amountPaid: Double
    let balanceDue: Double
    let paymentStatus: CustomOrderPaymentStatus
    let cashDrawerId: Int64?
    let cashDrawerName: String?
    let createdAt: String?

    var id: Int64 { customOrderId }
    var displayNumber: String {
        let trimmed = orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Custom #\(customOrderId)" : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case customOrderId = "custom_order_id"
        case orderNumber = "order_number"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case balanceDue = "balance_due"
        case paymentStatus = "payment_status"
        case cashDrawerId = "cash_drawer_id"
        case cashDrawerName = "cash_drawer_name"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customOrderId = try container.decodeCustomFlexibleInt64(forKey: .customOrderId)
        orderNumber = try container.decodeCustomFlexibleStringIfPresent(forKey: .orderNumber)
        totalAmount = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .totalAmount) ?? 0
        amountPaid = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .amountPaid) ?? 0
        balanceDue = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .balanceDue) ?? 0
        paymentStatus = CustomOrderPaymentStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .paymentStatus) ?? "UNPAID").uppercased()) ?? .unpaid
        cashDrawerId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .cashDrawerId)
        cashDrawerName = try container.decodeCustomFlexibleStringIfPresent(forKey: .cashDrawerName)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
    }
}

struct CustomOrderLineReturn: Decodable, Identifiable {
    let returnId: Int64
    let customOrderLineId: Int64?
    let returnType: String
    let refundAmount: Double
    let refundReason: String
    let payoutAmount: Double?
    let balanceAdjustmentAmount: Double?
    let createdAt: String?
    let returnedByName: String?

    var id: Int64 { returnId }
    var quantity: Double { returnType == "PARTIAL" ? 0.5 : 1 }

    enum CodingKeys: String, CodingKey {
        case returnId = "custom_order_line_return_id"
        case customOrderLineId = "custom_order_line_id"
        case returnType = "return_type"
        case refundAmount = "refund_amount"
        case refundReason = "reason"
        case payoutAmount = "payout_amount"
        case balanceAdjustmentAmount = "balance_reduction"
        case createdAt = "created_at"
        case returnedByName = "created_by_name"
    }
}

struct CustomOrderHistoryEntry: Decodable, Identifiable {
    let idValue: Int64
    let action: String
    let note: String?
    let createdAt: String?
    let userName: String?

    var id: Int64 { idValue }

    enum CodingKeys: String, CodingKey {
        case idValue = "custom_order_audit_id"
        case action = "action_type"
        case note = "reason"
        case createdAt = "created_at"
        case userName = "user_name"
    }
}

struct CustomOrderAuditEntry: Decodable, Identifiable {
    let auditId: Int64
    let orderId: Int64?
    let actionType: String
    let fieldName: String?
    let oldValue: String?
    let newValue: String?
    let reason: String?
    let userName: String?
    let createdAt: String?
    let deviceName: String?

    var id: Int64 { auditId }
    var title: String { actionType.replacingOccurrences(of: "_", with: " ").capitalized }

    enum CodingKeys: String, CodingKey {
        case auditId = "custom_order_audit_id"
        case orderId = "custom_order_id"
        case actionType = "action_type"
        case fieldName = "field_name"
        case oldValue = "old_value"
        case newValue = "new_value"
        case reason
        case userName = "user_name"
        case createdAt = "created_at"
        case deviceName = "device_name"
    }
}

struct CustomOrderStatusHistoryEntry: Decodable, Identifiable {
    let statusHistoryId: Int64
    let orderId: Int64?
    let oldStatus: CustomOrderStatus?
    let newStatus: CustomOrderStatus
    let reason: String?
    let userName: String?
    let createdAt: String?
    let deviceName: String?

    var id: Int64 { statusHistoryId }

    enum CodingKeys: String, CodingKey {
        case statusHistoryId = "custom_order_status_history_id"
        case orderId = "custom_order_id"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case reason
        case userName = "user_name"
        case createdAt = "created_at"
        case deviceName = "device_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        statusHistoryId = try container.decodeCustomFlexibleInt64(forKey: .statusHistoryId)
        orderId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .orderId)
        oldStatus = (try container.decodeCustomFlexibleStringIfPresent(forKey: .oldStatus)).flatMap { CustomOrderStatus(rawValue: $0.uppercased()) }
        newStatus = CustomOrderStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .newStatus) ?? "NEW").uppercased()) ?? .new
        reason = try container.decodeCustomFlexibleStringIfPresent(forKey: .reason)
        userName = try container.decodeCustomFlexibleStringIfPresent(forKey: .userName)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
        deviceName = try container.decodeCustomFlexibleStringIfPresent(forKey: .deviceName)
    }
}

struct CustomOrderLineDeliveryHistoryEntry: Decodable, Identifiable {
    let deliveryId: Int64
    let lineId: Int64?
    let itemName: String
    let variantName: String?
    let deliveredByName: String?
    let deliveryNotes: String?
    let deliveredAt: String?
    let deviceName: String?

    var id: Int64 { deliveryId }
    var displayName: String { variantName?.isEmpty == false ? "\(itemName) - \(variantName!)" : itemName }

    enum CodingKeys: String, CodingKey {
        case deliveryId = "custom_order_line_delivery_id"
        case lineId = "custom_order_line_id"
        case itemName = "item_name"
        case variantName = "variant_name"
        case deliveredByName = "delivered_by_name"
        case deliveryNotes = "delivery_notes"
        case deliveredAt = "delivered_at"
        case deviceName = "device_name"
    }
}

struct CustomOrderLineProductionHistoryEntry: Decodable, Identifiable {
    let productionHistoryId: Int64
    let lineId: Int64?
    let itemName: String
    let variantName: String?
    let oldStatus: CustomOrderProductionStatus?
    let newStatus: CustomOrderProductionStatus
    let notes: String?
    let updatedByName: String?
    let createdAt: String?
    let deviceName: String?

    var id: Int64 { productionHistoryId }
    var displayName: String { variantName?.isEmpty == false ? "\(itemName) - \(variantName!)" : itemName }

    enum CodingKeys: String, CodingKey {
        case productionHistoryId = "custom_order_line_production_history_id"
        case lineId = "custom_order_line_id"
        case itemName = "item_name"
        case variantName = "variant_name"
        case oldStatus = "old_status"
        case newStatus = "new_status"
        case notes
        case updatedByName = "updated_by_name"
        case createdAt = "created_at"
        case deviceName = "device_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productionHistoryId = try container.decodeCustomFlexibleInt64(forKey: .productionHistoryId)
        lineId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .lineId)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? "Custom Item"
        variantName = try container.decodeCustomFlexibleStringIfPresent(forKey: .variantName)
        oldStatus = (try container.decodeCustomFlexibleStringIfPresent(forKey: .oldStatus)).flatMap { CustomOrderProductionStatus(rawValue: $0.uppercased()) }
        newStatus = CustomOrderProductionStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .newStatus) ?? "NOT_STARTED").uppercased()) ?? .notStarted
        notes = try container.decodeCustomFlexibleStringIfPresent(forKey: .notes)
        updatedByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .updatedByName)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
        deviceName = try container.decodeCustomFlexibleStringIfPresent(forKey: .deviceName)
    }
}

struct CustomOrderCompanyPreferences: Codable {
    var companyName: String
    var receiptLogoURL: String
    var receiptHeaderLine: String
    var receiptFooterLine: String
    var showReceiptLogo: Bool
    var showSaleIdOnReceipt: Bool
    var showDeviceIdOnReceipt: Bool
    var showCustomerOnReceipt: Bool
    var showSkuOnReceipt: Bool
    var showItemDiscountsOnReceipt: Bool
    var showPaymentStatusOnReceipt: Bool
    var nextReceiptCounter: Int
    var customOrderSlipEnabled: Bool
    var customOrderSlipAutoPrint: Bool
    var customOrderSlipTitle: String
    var customOrderSlipContactLine: String
    var customOrderSlipEmailLine: String
    var customOrderSlipFooterNote: String
    var customOrderSlipBlankDetailLines: Int
    var customOrderSlipShowLogo: Bool
    var customOrderSlipShowOrderNumber: Bool
    var customOrderSlipShowDueDate: Bool
    var customOrderSlipShowCustomerPhone: Bool
    var customOrderSlipShowCustomerAccount: Bool
    var customOrderSlipShowStore: Bool
    var customOrderSlipShowDevice: Bool
    var customOrderSlipShowCashier: Bool
    var customOrderSlipShowLineItems: Bool
    var customOrderSlipShowPricing: Bool
    var customOrderSlipShowPaymentSummary: Bool
    var customOrderSlipShowPaymentReference: Bool
    var customOrderSlipShowTakenBy: Bool
    var customOrderSlipShowSignatures: Bool
    var customOrderMinimumDepositPercent: Double
    var customOrderRefundApprovalLimit: Double

    enum CodingKeys: String, CodingKey {
        case companyName = "company_name"
        case receiptLogoURL = "receipt_logo_url"
        case receiptHeaderLine = "receipt_header_line"
        case receiptFooterLine = "receipt_footer_line"
        case showReceiptLogo = "show_receipt_logo"
        case showSaleIdOnReceipt = "show_sale_id_on_receipt"
        case showDeviceIdOnReceipt = "show_device_id_on_receipt"
        case showCustomerOnReceipt = "show_customer_on_receipt"
        case showSkuOnReceipt = "show_sku_on_receipt"
        case showItemDiscountsOnReceipt = "show_item_discounts_on_receipt"
        case showPaymentStatusOnReceipt = "show_payment_status_on_receipt"
        case nextReceiptCounter = "next_receipt_counter"
        case customOrderSlipEnabled = "custom_order_slip_enabled"
        case customOrderSlipAutoPrint = "custom_order_slip_auto_print"
        case customOrderSlipTitle = "custom_order_slip_title"
        case customOrderSlipContactLine = "custom_order_slip_contact_line"
        case customOrderSlipEmailLine = "custom_order_slip_email_line"
        case customOrderSlipFooterNote = "custom_order_slip_footer_note"
        case customOrderSlipBlankDetailLines = "custom_order_slip_blank_detail_lines"
        case customOrderSlipShowLogo = "custom_order_slip_show_logo"
        case customOrderSlipShowOrderNumber = "custom_order_slip_show_order_number"
        case customOrderSlipShowDueDate = "custom_order_slip_show_due_date"
        case customOrderSlipShowCustomerPhone = "custom_order_slip_show_customer_phone"
        case customOrderSlipShowCustomerAccount = "custom_order_slip_show_customer_account"
        case customOrderSlipShowStore = "custom_order_slip_show_store"
        case customOrderSlipShowDevice = "custom_order_slip_show_device"
        case customOrderSlipShowCashier = "custom_order_slip_show_cashier"
        case customOrderSlipShowLineItems = "custom_order_slip_show_line_items"
        case customOrderSlipShowPricing = "custom_order_slip_show_pricing"
        case customOrderSlipShowPaymentSummary = "custom_order_slip_show_payment_summary"
        case customOrderSlipShowPaymentReference = "custom_order_slip_show_payment_reference"
        case customOrderSlipShowTakenBy = "custom_order_slip_show_taken_by"
        case customOrderSlipShowSignatures = "custom_order_slip_show_signatures"
        case customOrderMinimumDepositPercent = "custom_order_minimum_deposit_percent"
        case customOrderRefundApprovalLimit = "custom_order_refund_approval_limit"
    }

    init(
        companyName: String = "SmartStock",
        receiptLogoURL: String = "",
        receiptHeaderLine: String = "",
        receiptFooterLine: String = "Thank you",
        showReceiptLogo: Bool = true,
        showSaleIdOnReceipt: Bool = true,
        showDeviceIdOnReceipt: Bool = true,
        showCustomerOnReceipt: Bool = true,
        showSkuOnReceipt: Bool = true,
        showItemDiscountsOnReceipt: Bool = true,
        showPaymentStatusOnReceipt: Bool = true,
        nextReceiptCounter: Int = 1,
        customOrderSlipEnabled: Bool = true,
        customOrderSlipAutoPrint: Bool = false,
        customOrderSlipTitle: String = "Customer's Order Slip",
        customOrderSlipContactLine: String = "",
        customOrderSlipEmailLine: String = "",
        customOrderSlipFooterNote: String = "Please keep this slip for your records.",
        customOrderSlipBlankDetailLines: Int = 4,
        customOrderSlipShowLogo: Bool = true,
        customOrderSlipShowOrderNumber: Bool = true,
        customOrderSlipShowDueDate: Bool = true,
        customOrderSlipShowCustomerPhone: Bool = true,
        customOrderSlipShowCustomerAccount: Bool = true,
        customOrderSlipShowStore: Bool = true,
        customOrderSlipShowDevice: Bool = true,
        customOrderSlipShowCashier: Bool = true,
        customOrderSlipShowLineItems: Bool = true,
        customOrderSlipShowPricing: Bool = true,
        customOrderSlipShowPaymentSummary: Bool = true,
        customOrderSlipShowPaymentReference: Bool = true,
        customOrderSlipShowTakenBy: Bool = true,
        customOrderSlipShowSignatures: Bool = true,
        customOrderMinimumDepositPercent: Double,
        customOrderRefundApprovalLimit: Double
    ) {
        self.companyName = companyName
        self.receiptLogoURL = receiptLogoURL
        self.receiptHeaderLine = receiptHeaderLine
        self.receiptFooterLine = receiptFooterLine
        self.showReceiptLogo = showReceiptLogo
        self.showSaleIdOnReceipt = showSaleIdOnReceipt
        self.showDeviceIdOnReceipt = showDeviceIdOnReceipt
        self.showCustomerOnReceipt = showCustomerOnReceipt
        self.showSkuOnReceipt = showSkuOnReceipt
        self.showItemDiscountsOnReceipt = showItemDiscountsOnReceipt
        self.showPaymentStatusOnReceipt = showPaymentStatusOnReceipt
        self.nextReceiptCounter = max(nextReceiptCounter, 1)
        self.customOrderSlipEnabled = customOrderSlipEnabled
        self.customOrderSlipAutoPrint = customOrderSlipAutoPrint
        self.customOrderSlipTitle = customOrderSlipTitle
        self.customOrderSlipContactLine = customOrderSlipContactLine
        self.customOrderSlipEmailLine = customOrderSlipEmailLine
        self.customOrderSlipFooterNote = customOrderSlipFooterNote
        self.customOrderSlipBlankDetailLines = customOrderSlipBlankDetailLines
        self.customOrderSlipShowLogo = customOrderSlipShowLogo
        self.customOrderSlipShowOrderNumber = customOrderSlipShowOrderNumber
        self.customOrderSlipShowDueDate = customOrderSlipShowDueDate
        self.customOrderSlipShowCustomerPhone = customOrderSlipShowCustomerPhone
        self.customOrderSlipShowCustomerAccount = customOrderSlipShowCustomerAccount
        self.customOrderSlipShowStore = customOrderSlipShowStore
        self.customOrderSlipShowDevice = customOrderSlipShowDevice
        self.customOrderSlipShowCashier = customOrderSlipShowCashier
        self.customOrderSlipShowLineItems = customOrderSlipShowLineItems
        self.customOrderSlipShowPricing = customOrderSlipShowPricing
        self.customOrderSlipShowPaymentSummary = customOrderSlipShowPaymentSummary
        self.customOrderSlipShowPaymentReference = customOrderSlipShowPaymentReference
        self.customOrderSlipShowTakenBy = customOrderSlipShowTakenBy
        self.customOrderSlipShowSignatures = customOrderSlipShowSignatures
        self.customOrderMinimumDepositPercent = customOrderMinimumDepositPercent
        self.customOrderRefundApprovalLimit = customOrderRefundApprovalLimit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName) ?? "SmartStock"
        receiptLogoURL = try container.decodeIfPresent(String.self, forKey: .receiptLogoURL) ?? ""
        receiptHeaderLine = try container.decodeIfPresent(String.self, forKey: .receiptHeaderLine) ?? ""
        receiptFooterLine = try container.decodeIfPresent(String.self, forKey: .receiptFooterLine) ?? "Thank you"
        showReceiptLogo = try container.decodeIfPresent(Bool.self, forKey: .showReceiptLogo) ?? true
        showSaleIdOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showSaleIdOnReceipt) ?? true
        showDeviceIdOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showDeviceIdOnReceipt) ?? true
        showCustomerOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showCustomerOnReceipt) ?? true
        showSkuOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showSkuOnReceipt) ?? true
        showItemDiscountsOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showItemDiscountsOnReceipt) ?? true
        showPaymentStatusOnReceipt = try container.decodeIfPresent(Bool.self, forKey: .showPaymentStatusOnReceipt) ?? true
        nextReceiptCounter = max(try container.decodeIfPresent(Int.self, forKey: .nextReceiptCounter) ?? 1, 1)
        customOrderSlipEnabled = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipEnabled) ?? true
        customOrderSlipAutoPrint = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipAutoPrint) ?? false
        customOrderSlipTitle = try container.decodeIfPresent(String.self, forKey: .customOrderSlipTitle) ?? "Customer's Order Slip"
        customOrderSlipContactLine = try container.decodeIfPresent(String.self, forKey: .customOrderSlipContactLine) ?? ""
        customOrderSlipEmailLine = try container.decodeIfPresent(String.self, forKey: .customOrderSlipEmailLine) ?? ""
        customOrderSlipFooterNote = try container.decodeIfPresent(String.self, forKey: .customOrderSlipFooterNote) ?? "Please keep this slip for your records."
        customOrderSlipBlankDetailLines = try container.decodeIfPresent(Int.self, forKey: .customOrderSlipBlankDetailLines) ?? 4
        customOrderSlipShowLogo = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowLogo) ?? true
        customOrderSlipShowOrderNumber = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowOrderNumber) ?? true
        customOrderSlipShowDueDate = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowDueDate) ?? true
        customOrderSlipShowCustomerPhone = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowCustomerPhone) ?? true
        customOrderSlipShowCustomerAccount = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowCustomerAccount) ?? true
        customOrderSlipShowStore = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowStore) ?? true
        customOrderSlipShowDevice = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowDevice) ?? true
        customOrderSlipShowCashier = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowCashier) ?? true
        customOrderSlipShowLineItems = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowLineItems) ?? true
        customOrderSlipShowPricing = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowPricing) ?? true
        customOrderSlipShowPaymentSummary = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowPaymentSummary) ?? true
        customOrderSlipShowPaymentReference = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowPaymentReference) ?? true
        customOrderSlipShowTakenBy = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowTakenBy) ?? true
        customOrderSlipShowSignatures = try container.decodeIfPresent(Bool.self, forKey: .customOrderSlipShowSignatures) ?? true
        customOrderMinimumDepositPercent = try container.decodeIfPresent(Double.self, forKey: .customOrderMinimumDepositPercent) ?? 0
        customOrderRefundApprovalLimit = try container.decodeIfPresent(Double.self, forKey: .customOrderRefundApprovalLimit) ?? 0
    }
}

struct CustomOrder: Decodable, Identifiable {
    let customOrderId: Int64
    let orderNumber: String?
    let customerId: Int
    let customerName: String
    let customerPhone: String
    let status: CustomOrderStatus
    let paymentStatus: CustomOrderPaymentStatus
    let paymentMethod: String?
    let paymentReference: String?
    let cashDrawerId: Int64?
    let cashDrawerName: String?
    let dueDate: String?
    let orderNotes: String?
    let totalAmount: Double
    let amountPaid: Double
    let refundedAmount: Double
    let balanceDue: Double
    let minimumDepositRequired: Double?
    let depositOverrideReason: String?
    let depositOverrideByUserId: Int?
    let depositOverrideByName: String?
    let locationId: Int?
    let locationName: String?
    let deviceId: String?
    let deviceName: String?
    let takenByUserId: Int?
    let takenByName: String?
    let assignedToUserId: Int?
    let assignedToName: String?
    let assignedByUserId: Int?
    let assignedByName: String?
    let assignedAt: String?
    let completedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let lines: [CustomOrderLine]
    let payments: [CustomOrderPayment]

    var id: Int64 { customOrderId }
    var displayNumber: String { orderNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? orderNumber! : "Custom #\(customOrderId)" }
    var totalText: String { String(format: "$%.2f", totalAmount) }
    var balanceText: String { String(format: "$%.2f", balanceDue) }

    enum CodingKeys: String, CodingKey {
        case customOrderId = "custom_order_id"
        case orderNumber = "order_number"
        case customerId = "customer_id"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case status
        case paymentStatus = "payment_status"
        case paymentMethod = "payment_method"
        case paymentReference = "payment_reference"
        case cashDrawerId = "cash_drawer_id"
        case cashDrawerName = "cash_drawer_name"
        case dueDate = "due_date"
        case orderNotes = "order_notes"
        case totalAmount = "total_amount"
        case amountPaid = "amount_paid"
        case refundedAmount = "refunded_amount"
        case balanceDue = "balance_due"
        case minimumDepositRequired = "minimum_deposit_required"
        case depositOverrideReason = "deposit_override_reason"
        case depositOverrideByUserId = "deposit_override_by_user_id"
        case depositOverrideByName = "deposit_override_by_name"
        case locationId = "location_id"
        case locationName = "location_name"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case takenByUserId = "taken_by_user_id"
        case takenByName = "taken_by_name"
        case assignedToUserId = "assigned_to_user_id"
        case assignedToName = "assigned_to_name"
        case assignedByUserId = "assigned_by_user_id"
        case assignedByName = "assigned_by_name"
        case assignedAt = "assigned_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lines = "custom_order_lines"
        case payments = "custom_order_payments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customOrderId = try container.decodeCustomFlexibleInt64(forKey: .customOrderId)
        orderNumber = try container.decodeCustomFlexibleStringIfPresent(forKey: .orderNumber)
        customerId = try container.decodeCustomFlexibleIntIfPresent(forKey: .customerId) ?? 0
        customerName = try container.decodeIfPresent(String.self, forKey: .customerName) ?? "Customer"
        customerPhone = try container.decodeCustomFlexibleStringIfPresent(forKey: .customerPhone) ?? ""
        status = CustomOrderStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .status) ?? "NEW").uppercased()) ?? .new
        paymentStatus = CustomOrderPaymentStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .paymentStatus) ?? "UNPAID").uppercased()) ?? .unpaid
        paymentMethod = try container.decodeCustomFlexibleStringIfPresent(forKey: .paymentMethod)
        paymentReference = try container.decodeCustomFlexibleStringIfPresent(forKey: .paymentReference)
        cashDrawerId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .cashDrawerId)
        cashDrawerName = try container.decodeCustomFlexibleStringIfPresent(forKey: .cashDrawerName)
        dueDate = try container.decodeCustomFlexibleStringIfPresent(forKey: .dueDate)
        orderNotes = try container.decodeCustomFlexibleStringIfPresent(forKey: .orderNotes)
        totalAmount = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .totalAmount) ?? 0
        amountPaid = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .amountPaid) ?? 0
        refundedAmount = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .refundedAmount) ?? 0
        balanceDue = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .balanceDue) ?? max(totalAmount - amountPaid, 0)
        minimumDepositRequired = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .minimumDepositRequired)
        depositOverrideReason = try container.decodeCustomFlexibleStringIfPresent(forKey: .depositOverrideReason)
        depositOverrideByUserId = try container.decodeCustomFlexibleIntIfPresent(forKey: .depositOverrideByUserId)
        depositOverrideByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .depositOverrideByName)
        locationId = try container.decodeCustomFlexibleIntIfPresent(forKey: .locationId)
        locationName = try container.decodeCustomFlexibleStringIfPresent(forKey: .locationName)
        deviceId = try container.decodeCustomFlexibleStringIfPresent(forKey: .deviceId)
        deviceName = try container.decodeCustomFlexibleStringIfPresent(forKey: .deviceName)
        takenByUserId = try container.decodeCustomFlexibleIntIfPresent(forKey: .takenByUserId)
        takenByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .takenByName)
        assignedToUserId = try container.decodeCustomFlexibleIntIfPresent(forKey: .assignedToUserId)
        assignedToName = try container.decodeCustomFlexibleStringIfPresent(forKey: .assignedToName)
        assignedByUserId = try container.decodeCustomFlexibleIntIfPresent(forKey: .assignedByUserId)
        assignedByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .assignedByName)
        assignedAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .assignedAt)
        completedAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .completedAt)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
        updatedAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .updatedAt)
        lines = (try? container.decodeIfPresent([CustomOrderLine].self, forKey: .lines)) ?? []
        payments = (try? container.decodeIfPresent([CustomOrderPayment].self, forKey: .payments)) ?? []
    }
}

struct CustomOrderLine: Decodable, Identifiable {
    let customOrderLineId: Int64
    let customOrderId: Int64?
    let customItemId: Int64
    let variantId: Int64?
    let itemName: String
    let variantName: String?
    let itemType: CustomOrderItemType
    let pricingType: CustomOrderPricingType
    let quantity: Double
    let unitPrice: Double
    let originalLineTotal: Double
    let lineDiscountPercent: Double
    let lineDiscountAmount: Double
    let printMaterialName: String?
    let printSizeName: String?
    let printCharge: Double?
    let lineDiscountByName: String?
    let lineDiscountReason: String?
    let lineTotal: Double
    let originalBasePrice: Double?
    let priceOverridePrice: Double?
    let priceOverrideReason: String?
    let priceOverrideByName: String?
    let widthValue: Double?
    let lengthValue: Double?
    let dimensionUnit: String?
    let areaValue: Double?
    let areaUnit: String?
    let areaPrice: Double?
    let baseItemPrice: Double?
    let customizationDetails: String?
    let lineNotes: String?
    let deliveryStatus: CustomOrderDeliveryStatus
    let deliveredAt: String?
    let deliveredByName: String?
    let productionStatus: CustomOrderProductionStatus
    let productionUpdatedAt: String?
    let productionUpdatedByName: String?
    let sortOrder: Int?
    let createdAt: String?
    let printAddons: [CustomOrderLinePrintAddon]
    let returns: [CustomOrderLineReturn]

    var id: Int64 { customOrderLineId }
    var priceText: String { String(format: "$%.2f", unitPrice) }
    var totalText: String { String(format: "$%.2f", lineTotal) }
    var displayName: String { variantName?.isEmpty == false ? "\(itemName) - \(variantName!)" : itemName }
    var orderInstructions: String? { lineNotes }

    enum CodingKeys: String, CodingKey {
        case customOrderLineId = "custom_order_line_id"
        case customOrderId = "custom_order_id"
        case customItemId = "custom_item_id"
        case variantId = "custom_variant_id"
        case itemName = "item_name"
        case variantName = "variant_name"
        case itemType = "product_type"
        case pricingType = "pricing_type"
        case quantity
        case unitPrice = "unit_price"
        case originalLineTotal = "original_line_total"
        case lineDiscountPercent = "line_discount_percent"
        case lineDiscountAmount = "line_discount_amount"
        case printMaterialName = "print_material_name"
        case printSizeName = "print_size_name"
        case printCharge = "print_charge"
        case lineDiscountByName = "line_discount_by_name"
        case lineDiscountReason = "line_discount_reason"
        case lineTotal = "line_total"
        case originalBasePrice = "original_base_price"
        case priceOverridePrice = "price_override_price"
        case priceOverrideReason = "price_override_reason"
        case priceOverrideByName = "price_override_by_name"
        case widthValue = "width_value"
        case lengthValue = "length_value"
        case dimensionUnit = "dimension_unit"
        case areaValue = "area_value"
        case areaUnit = "area_unit"
        case areaPrice = "area_price"
        case baseItemPrice = "base_item_price"
        case customizationDetails = "customization_details"
        case lineNotes = "order_instructions"
        case deliveryStatus = "delivery_status"
        case deliveredAt = "delivered_at"
        case deliveredByName = "delivered_by_name"
        case productionStatus = "production_status"
        case productionUpdatedAt = "production_updated_at"
        case productionUpdatedByName = "production_updated_by_name"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case printAddons = "custom_order_line_print_addons"
        case returns = "custom_order_line_returns"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        customOrderLineId = try container.decodeCustomFlexibleInt64(forKey: .customOrderLineId)
        customOrderId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .customOrderId)
        customItemId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .customItemId) ?? 0
        variantId = try container.decodeCustomFlexibleInt64IfPresent(forKey: .variantId)
        itemName = try container.decodeIfPresent(String.self, forKey: .itemName) ?? "Custom Item"
        variantName = try container.decodeCustomFlexibleStringIfPresent(forKey: .variantName)
        itemType = CustomOrderItemType(rawValue: (try container.decodeIfPresent(String.self, forKey: .itemType) ?? "INVENTORY").uppercased()) ?? .inventory
        pricingType = CustomOrderPricingType(rawValue: (try container.decodeIfPresent(String.self, forKey: .pricingType) ?? "FIXED").uppercased()) ?? .fixed
        quantity = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .quantity) ?? 1
        unitPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .unitPrice) ?? 0
        originalLineTotal = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .originalLineTotal) ?? unitPrice * quantity
        lineDiscountPercent = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .lineDiscountPercent) ?? 0
        lineDiscountAmount = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .lineDiscountAmount) ?? 0
        printMaterialName = try container.decodeCustomFlexibleStringIfPresent(forKey: .printMaterialName)
        printSizeName = try container.decodeCustomFlexibleStringIfPresent(forKey: .printSizeName)
        printCharge = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .printCharge)
        lineDiscountByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .lineDiscountByName)
        lineDiscountReason = try container.decodeCustomFlexibleStringIfPresent(forKey: .lineDiscountReason)
        lineTotal = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .lineTotal) ?? originalLineTotal - lineDiscountAmount
        originalBasePrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .originalBasePrice)
        priceOverridePrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .priceOverridePrice)
        priceOverrideReason = try container.decodeCustomFlexibleStringIfPresent(forKey: .priceOverrideReason)
        priceOverrideByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .priceOverrideByName)
        widthValue = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .widthValue)
        lengthValue = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .lengthValue)
        dimensionUnit = try container.decodeCustomFlexibleStringIfPresent(forKey: .dimensionUnit)
        areaValue = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .areaValue)
        areaUnit = try container.decodeCustomFlexibleStringIfPresent(forKey: .areaUnit)
        areaPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .areaPrice)
        baseItemPrice = try container.decodeCustomFlexibleDoubleIfPresent(forKey: .baseItemPrice)
        customizationDetails = try container.decodeCustomFlexibleStringIfPresent(forKey: .customizationDetails)
        lineNotes = try container.decodeCustomFlexibleStringIfPresent(forKey: .lineNotes)
        deliveryStatus = CustomOrderDeliveryStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .deliveryStatus) ?? "PENDING").uppercased()) ?? .pending
        deliveredAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .deliveredAt)
        deliveredByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .deliveredByName)
        productionStatus = CustomOrderProductionStatus(rawValue: (try container.decodeIfPresent(String.self, forKey: .productionStatus) ?? "NOT_STARTED").uppercased()) ?? .notStarted
        productionUpdatedAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .productionUpdatedAt)
        productionUpdatedByName = try container.decodeCustomFlexibleStringIfPresent(forKey: .productionUpdatedByName)
        sortOrder = try container.decodeCustomFlexibleIntIfPresent(forKey: .sortOrder)
        createdAt = try container.decodeCustomFlexibleStringIfPresent(forKey: .createdAt)
        printAddons = (try? container.decodeIfPresent([CustomOrderLinePrintAddon].self, forKey: .printAddons)) ?? []
        returns = (try? container.decodeIfPresent([CustomOrderLineReturn].self, forKey: .returns)) ?? []
    }
}

struct CustomOrderEmployee: Decodable, Identifiable, Hashable {
    let userId: Int
    let fullName: String
    let username: String?

    var id: Int { userId }
    var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (username ?? "User #\(userId)") : trimmed
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fullName = "full_name"
        case username
    }
}

struct CustomOrderItemDraft {
    var itemName = ""
    var sku = ""
    var barcode = ""
    var description = ""
    var itemType: CustomOrderItemType = .inventory
    var pricingType: CustomOrderPricingType = .fixed
    var fixedPrice = ""
    var areaPrice = ""
    var areaPriceUnit = "sq ft"
    var dimensionUnit = "in"
    var maxWidth = ""
    var maxLength = ""
    var imageUrl = ""
    var quantityOnHand = "0"
    var reorderLevel = "0"
    var hasVariants = false
    var isActive = true

    init() {}

    init(item: CustomOrderItem) {
        itemName = item.itemName
        sku = item.sku ?? ""
        barcode = item.barcode ?? ""
        description = item.description ?? ""
        itemType = item.itemType
        pricingType = item.pricingType
        fixedPrice = item.fixedPrice.map { String(format: "%.2f", $0) } ?? ""
        areaPrice = item.areaPrice.map { String(format: "%.2f", $0) } ?? ""
        areaPriceUnit = Self.normalizedAreaUnit(item.areaPriceUnit)
        dimensionUnit = Self.normalizedDimensionUnit(item.dimensionUnit)
        maxWidth = item.maxWidth.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? ""
        maxLength = item.maxLength.map { $0.rounded() == $0 ? String(Int($0)) : String($0) } ?? ""
        imageUrl = item.imageUrl ?? ""
        quantityOnHand = Self.numberText(item.quantityOnHand)
        reorderLevel = Self.numberText(item.reorderLevel)
        hasVariants = item.hasVariants
        isActive = item.isActive
    }

    private static func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func normalizedAreaUnit(_ value: String?) -> String {
        switch normalizedUnit(value) {
        case "sqft", "squarefeet", "squarefoot": return "sq ft"
        case "sqin", "squareinches", "squareinch": return "sq in"
        case "sqm", "squaremeters", "squaremeter": return "sq m"
        case "sqcm", "squarecentimeters", "squarecentimeter": return "sq cm"
        default: return "sq ft"
        }
    }

    private static func normalizedDimensionUnit(_ value: String?) -> String {
        switch normalizedUnit(value) {
        case "in", "inch", "inches": return "in"
        case "ft", "foot", "feet": return "ft"
        case "cm", "centimeter", "centimeters": return "cm"
        case "mm", "millimeter", "millimeters": return "mm"
        case "m", "meter", "meters": return "m"
        default: return "in"
        }
    }

    private static func normalizedUnit(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
    }
}

struct CustomOrderVariantDraft {
    var parentItemName = ""
    var variantName = ""
    var sku = ""
    var barcode = ""
    var fixedPrice = ""
    var quantityOnHand = "0"
    var reorderLevel = "0"
    var imageUrl = ""
    var isActive = true

    init() {}

    init(variant: CustomOrderItemVariant, parentItemName: String = "") {
        self.parentItemName = parentItemName
        variantName = variant.variantName
        sku = variant.sku ?? ""
        barcode = variant.barcode ?? ""
        fixedPrice = variant.price.map { String(format: "%.2f", $0) } ?? ""
        quantityOnHand = Self.numberText(variant.quantityOnHand)
        reorderLevel = Self.numberText(variant.reorderLevel)
        imageUrl = variant.imageUrl ?? ""
        isActive = variant.isActive
    }

    private static func numberText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

struct CustomOrderPrintAddonDraft: Identifiable, Hashable {
    let id = UUID()
    var material: CustomOrderPrintMaterial?
    var preset: CustomOrderPrintSizePreset?
    var pricingMode = "FIXED_PRESET"
    var printDescription = ""
    var priceText = ""
    var lineCountText = "1"

    var price: Double {
        let unitPrice = enteredPrice ?? preset?.fixedPrice ?? 0
        if pricingMode == "PER_LINE" {
            return unitPrice * Double(lineCount)
        }
        return unitPrice
    }

    var lineCount: Int {
        max(Int(lineCountText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 1)
    }

    var unitPriceText: String {
        String(format: "$%.2f", enteredPrice ?? preset?.fixedPrice ?? 0)
    }

    private var enteredPrice: Double? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }
}

struct CustomOrderDraftLine: Identifiable, Hashable {
    let id = UUID()
    let item: CustomOrderItem
    var variant: CustomOrderItemVariant?
    var quantityText = "1"
    var unitPriceText = ""
    var widthText = ""
    var lengthText = ""
    var dimensionUnit = "in"
    var areaUnit = "sq ft"
    var areaPriceText = ""
    var discountPercentText = ""
    var discountReason = ""
    var priceOverrideReason = ""
    var customizationDetails = ""
    var lineNotes = ""
    var printAddons: [CustomOrderPrintAddonDraft] = []

    var quantity: Double { max(Double(quantityText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 1, 0) }
    var widthValue: Double? { Double(widthText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var lengthValue: Double? { Double(lengthText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    var areaValue: Double? {
        guard let widthValue, let lengthValue else { return nil }
        return Self.convertedArea(width: widthValue, length: lengthValue, dimensionUnit: dimensionUnit, areaUnit: areaUnit)
    }
    var basePrice: Double? {
        if let variant { return variant.price }
        return item.fixedPrice
    }
    var areaPrice: Double? { Double(areaPriceText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? basePrice }
    var hasPriceOverride: Bool {
        switch item.pricingType {
        case .fixed:
            return false
        case .variable:
            guard let enteredPrice = Double(unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let basePrice else { return false }
            return abs(enteredPrice - basePrice) > 0.0001
        case .area:
            guard let areaPrice, let basePrice else { return false }
            return abs(areaPrice - basePrice) > 0.0001
        }
    }
    var unitPrice: Double? {
        switch item.pricingType {
        case .fixed:
            return basePrice
        case .variable:
            return Double(unitPriceText.trimmingCharacters(in: .whitespacesAndNewlines))
        case .area:
            guard let areaValue, let areaPrice else { return nil }
            return areaValue * areaPrice
        }
    }
    var printAddonTotal: Double { printAddons.reduce(0) { $0 + $1.price } }
    var originalLineTotal: Double { ((unitPrice ?? 0) * quantity) + printAddonTotal }
    var discountPercent: Double { max(Double(discountPercentText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0, 0) }
    var discountAmount: Double { originalLineTotal * min(discountPercent, 100) / 100 }
    var lineTotal: Double { max(originalLineTotal - discountAmount, 0) }

    var areaText: String {
        guard let areaValue else { return "" }
        return String(format: "%.2f %@", areaValue, areaUnit)
    }

    private static func convertedArea(width: Double, length: Double, dimensionUnit: String, areaUnit: String) -> Double {
        let widthMeters = width * metersPerUnit(dimensionUnit)
        let lengthMeters = length * metersPerUnit(dimensionUnit)
        let squareMeters = widthMeters * lengthMeters
        return squareMeters / squareMetersPerAreaUnit(areaUnit)
    }

    private static func metersPerUnit(_ unit: String) -> Double {
        switch normalizedUnit(unit) {
        case "in", "inch", "inches": return 0.0254
        case "ft", "foot", "feet": return 0.3048
        case "cm", "centimeter", "centimeters": return 0.01
        case "mm", "millimeter", "millimeters": return 0.001
        case "m", "meter", "meters": return 1
        default: return 1
        }
    }

    private static func squareMetersPerAreaUnit(_ unit: String) -> Double {
        switch normalizedUnit(unit) {
        case "sqin", "squareinch", "squareinches": return 0.00064516
        case "sqft", "squarefoot", "squarefeet": return 0.09290304
        case "sqcm", "squarecentimeter", "squarecentimeters": return 0.0001
        case "sqm", "squaremeter", "squaremeters": return 1
        default: return 1
        }
    }

    private static func normalizedUnit(_ unit: String) -> String {
        unit
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
    }

    func singleQuantityCopy() -> CustomOrderDraftLine {
        var copy = CustomOrderDraftLine(item: item, variant: variant)
        copy.quantityText = "1"
        copy.unitPriceText = unitPriceText
        copy.widthText = widthText
        copy.lengthText = lengthText
        copy.dimensionUnit = dimensionUnit
        copy.areaUnit = areaUnit
        copy.areaPriceText = areaPriceText
        copy.discountPercentText = discountPercentText
        copy.discountReason = discountReason
        copy.priceOverrideReason = priceOverrideReason
        copy.customizationDetails = customizationDetails
        copy.lineNotes = lineNotes
        copy.printAddons = printAddons
        return copy
    }
}

extension KeyedDecodingContainer where Key: CodingKey {
    func decodeCustomFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return String(value) }
        if let value = try decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try decodeIfPresent(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func decodeCustomFlexibleInt(forKey key: Key) throws -> Int {
        if let value = try decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return Int(value) }
        if let value = try decodeIfPresent(String.self, forKey: key), let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return parsed }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected integer-compatible value.")
    }

    func decodeCustomFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return Int(value) }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func decodeCustomFlexibleInt64(forKey key: Key) throws -> Int64 {
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(String.self, forKey: key), let parsed = Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return parsed }
        throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected int64-compatible value.")
    }

    func decodeCustomFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func decodeCustomFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try decodeIfPresent(Int64.self, forKey: key) { return Double(value) }
        if let value = try decodeIfPresent(String.self, forKey: key) { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func decodeCustomFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let value = try decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try decodeIfPresent(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "t", "1", "yes", "y": return true
            case "false", "f", "0", "no", "n": return false
            default: return nil
            }
        }
        return nil
    }
}
