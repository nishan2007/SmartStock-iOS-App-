//
//  MaintenanceModels.swift
//  SmartStock
//

import Foundation

enum MaintenanceMachineStatus: String, CaseIterable, Identifiable, Codable {
    case active = "ACTIVE"
    case needsService = "NEEDS_SERVICE"
    case down = "DOWN"
    case retired = "RETIRED"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active:
            return "Active"
        case .needsService:
            return "Needs Service"
        case .down:
            return "Down"
        case .retired:
            return "Retired"
        }
    }
}

struct MaintenanceLocationRef: Decodable, Hashable {
    let name: String?
}

struct MaintenanceMachine: Decodable, Identifiable, Hashable {
    let id: Int
    let machineName: String
    let assetTag: String?
    let serialNumber: String?
    let manufacturer: String?
    let model: String?
    let machineType: String?
    let locationId: Int?
    let locationName: String?
    let status: MaintenanceMachineStatus
    let purchaseDate: String?
    let warrantyExpirationDate: String?
    let lastServiceDate: String?
    let nextServiceDate: String?
    let notes: String?
    let createdAt: String?
    let updatedAt: String?
    let locations: MaintenanceLocationRef?

    enum CodingKeys: String, CodingKey {
        case id = "machine_id"
        case machineName = "machine_name"
        case assetTag = "asset_tag"
        case serialNumber = "serial_number"
        case manufacturer
        case model
        case machineType = "machine_type"
        case locationId = "location_id"
        case locationName = "location_name"
        case status
        case purchaseDate = "purchase_date"
        case warrantyExpirationDate = "warranty_expiration_date"
        case lastServiceDate = "last_service_date"
        case nextServiceDate = "next_service_date"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case locations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        machineName = try container.decode(String.self, forKey: .machineName)
        assetTag = try container.decodeIfPresent(String.self, forKey: .assetTag)
        serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber)
        manufacturer = try container.decodeIfPresent(String.self, forKey: .manufacturer)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        machineType = try container.decodeIfPresent(String.self, forKey: .machineType)
        locationId = try container.decodeIfPresent(Int.self, forKey: .locationId)
        locationName = try container.decodeIfPresent(String.self, forKey: .locationName)
        status = try container.decodeIfPresent(MaintenanceMachineStatus.self, forKey: .status) ?? .active
        purchaseDate = try container.decodeIfPresent(String.self, forKey: .purchaseDate)
        warrantyExpirationDate = try container.decodeIfPresent(String.self, forKey: .warrantyExpirationDate)
        lastServiceDate = try container.decodeIfPresent(String.self, forKey: .lastServiceDate)
        nextServiceDate = try container.decodeIfPresent(String.self, forKey: .nextServiceDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        locations = try container.decodeIfPresent(MaintenanceLocationRef.self, forKey: .locations)
    }

    var displayLocationName: String {
        let joinedName = locations?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !joinedName.isEmpty {
            return joinedName
        }

        let legacyName = locationName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return legacyName.isEmpty ? "No Store" : legacyName
    }

    var subtitle: String {
        [assetTag, machineType, displayLocationName]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " • ")
    }
}

struct MaintenancePart: Decodable, Identifiable, Hashable {
    let id: Int
    let partName: String
    let partNumber: String?
    let category: String?
    let quantityOnHand: Decimal
    let reorderPoint: Decimal
    let reorderQuantity: Decimal
    let unitCost: Decimal?
    let vendorName: String?
    let binLocation: String?
    let isActive: Bool
    let notes: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id = "part_id"
        case partName = "part_name"
        case partNumber = "part_number"
        case category
        case quantityOnHand = "quantity_on_hand"
        case reorderPoint = "reorder_point"
        case reorderQuantity = "reorder_quantity"
        case unitCost = "unit_cost"
        case vendorName = "vendor_name"
        case binLocation = "bin_location"
        case isActive = "is_active"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        partName = try container.decode(String.self, forKey: .partName)
        partNumber = try container.decodeIfPresent(String.self, forKey: .partNumber)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        quantityOnHand = try container.decodeFlexibleDecimalIfPresent(forKey: .quantityOnHand) ?? 0
        reorderPoint = try container.decodeFlexibleDecimalIfPresent(forKey: .reorderPoint) ?? 0
        reorderQuantity = try container.decodeFlexibleDecimalIfPresent(forKey: .reorderQuantity) ?? 0
        unitCost = try container.decodeIfPresent(Decimal.self, forKey: .unitCost)
        vendorName = try container.decodeIfPresent(String.self, forKey: .vendorName)
        binLocation = try container.decodeIfPresent(String.self, forKey: .binLocation)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var detailText: String {
        [partNumber, category, binLocation]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: " • ")
    }
}

struct MaintenancePartRef: Decodable, Hashable {
    let id: Int
    let partName: String
    let partNumber: String?

    enum CodingKeys: String, CodingKey {
        case id = "part_id"
        case partName = "part_name"
        case partNumber = "part_number"
    }
}

struct MaintenanceMachinePart: Decodable, Identifiable, Hashable {
    let id: Int
    let machineId: Int
    let partId: Int
    let notes: String?
    let createdAt: String?
    let updatedAt: String?
    let maintenanceParts: MaintenancePartRef?

    enum CodingKeys: String, CodingKey {
        case id = "machine_part_id"
        case machineId = "machine_id"
        case partId = "part_id"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case maintenanceParts = "maintenance_parts"
    }

    var partName: String {
        maintenanceParts?.partName ?? "Part #\(partId)"
    }

    var partNumberText: String {
        let trimmed = maintenanceParts?.partNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "No part number" : trimmed
    }
}

struct MaintenanceLog: Decodable, Identifiable, Hashable {
    let id: Int
    let machineId: Int?
    let serviceType: String?
    let serviceDate: String?
    let technicianName: String?
    let laborHours: Decimal
    let totalCost: Decimal
    let summary: String?
    let details: String?
    let partsUsed: String?
    let createdByUserId: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case fallbackId = "id"
        case maintenanceLogId = "maintenance_log_id"
        case id = "log_id"
        case machineId = "machine_id"
        case serviceType = "service_type"
        case logType = "log_type"
        case type
        case serviceDate = "service_date"
        case logDate = "log_date"
        case technicianName = "technician_name"
        case performedBy = "performed_by"
        case laborHours = "labor_hours"
        case totalCost = "total_cost"
        case summary
        case details
        case partsUsed = "parts_used"
        case createdByUserId = "created_by_user_id"
        case description
        case notes
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
            ?? container.decodeIfPresent(Int.self, forKey: .maintenanceLogId)
            ?? container.decode(Int.self, forKey: .fallbackId)
        machineId = try container.decodeIfPresent(Int.self, forKey: .machineId)
        serviceType = try container.decodeIfPresent(String.self, forKey: .serviceType)
            ?? container.decodeIfPresent(String.self, forKey: .logType)
            ?? container.decodeIfPresent(String.self, forKey: .type)
        serviceDate = try container.decodeIfPresent(String.self, forKey: .serviceDate)
            ?? container.decodeIfPresent(String.self, forKey: .logDate)
        technicianName = try container.decodeIfPresent(String.self, forKey: .technicianName)
            ?? container.decodeIfPresent(String.self, forKey: .performedBy)
        laborHours = try container.decodeFlexibleDecimalIfPresent(forKey: .laborHours) ?? 0
        totalCost = try container.decodeFlexibleDecimalIfPresent(forKey: .totalCost) ?? 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
            ?? container.decodeIfPresent(String.self, forKey: .description)
        details = try container.decodeIfPresent(String.self, forKey: .details)
            ?? container.decodeIfPresent(String.self, forKey: .notes)
        partsUsed = try container.decodeIfPresent(String.self, forKey: .partsUsed)
        createdByUserId = try container.decodeIfPresent(Int.self, forKey: .createdByUserId)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
    }

    var displayServiceType: String {
        serviceType?.maintenanceDisplayText ?? "Service"
    }
}

struct MaintenanceTicket: Decodable, Identifiable, Hashable {
    let id: Int
    let machineId: Int?
    let openedAt: String?
    let openedByUserId: Int?
    let status: String?
    let priority: String?
    let assignedToName: String?
    let dueDate: String?
    let problemSummary: String?
    let resolutionSummary: String?
    let notes: String?
    let resolvedAt: String?
    let closedAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case fallbackId = "id"
        case maintenanceTicketId = "maintenance_ticket_id"
        case id = "ticket_id"
        case machineId = "machine_id"
        case openedAt = "opened_at"
        case openedByUserId = "opened_by_user_id"
        case title
        case subject
        case description
        case status
        case priority
        case assignedToName = "assigned_to_name"
        case dueDate = "due_date"
        case problemSummary = "problem_summary"
        case resolutionSummary = "resolution_summary"
        case notes
        case resolvedAt = "resolved_at"
        case closedAt = "closed_at"
        case requestedBy = "requested_by"
        case assignedTo = "assigned_to"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
            ?? container.decodeIfPresent(Int.self, forKey: .maintenanceTicketId)
            ?? container.decode(Int.self, forKey: .fallbackId)
        machineId = try container.decodeIfPresent(Int.self, forKey: .machineId)
        openedAt = try container.decodeIfPresent(String.self, forKey: .openedAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
        openedByUserId = try container.decodeIfPresent(Int.self, forKey: .openedByUserId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        priority = try container.decodeIfPresent(String.self, forKey: .priority)
        assignedToName = try container.decodeIfPresent(String.self, forKey: .assignedToName)
            ?? container.decodeIfPresent(String.self, forKey: .assignedTo)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        problemSummary = try container.decodeIfPresent(String.self, forKey: .problemSummary)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .subject)
            ?? container.decodeIfPresent(String.self, forKey: .description)
        resolutionSummary = try container.decodeIfPresent(String.self, forKey: .resolutionSummary)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
            ?? container.decodeIfPresent(String.self, forKey: .requestedBy)
        resolvedAt = try container.decodeIfPresent(String.self, forKey: .resolvedAt)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }

    var displayStatus: String {
        status?.maintenanceDisplayText ?? "Open"
    }

    var displayPriority: String {
        priority?.maintenanceDisplayText ?? "Normal"
    }
}

struct MaintenanceMachineDraft {
    var id: Int?
    var machineName = ""
    var assetTag = ""
    var serialNumber = ""
    var manufacturer = ""
    var model = ""
    var machineType = ""
    var locationId: Int?
    var status: MaintenanceMachineStatus = .active
    var purchaseDate = ""
    var warrantyExpirationDate = ""
    var lastServiceDate = ""
    var nextServiceDate = ""
    var notes = ""

    init() {}

    init(machine: MaintenanceMachine) {
        id = machine.id
        machineName = machine.machineName
        assetTag = machine.assetTag ?? ""
        serialNumber = machine.serialNumber ?? ""
        manufacturer = machine.manufacturer ?? ""
        model = machine.model ?? ""
        machineType = machine.machineType ?? ""
        locationId = machine.locationId
        status = machine.status
        purchaseDate = machine.purchaseDate ?? ""
        warrantyExpirationDate = machine.warrantyExpirationDate ?? ""
        lastServiceDate = machine.lastServiceDate ?? ""
        nextServiceDate = machine.nextServiceDate ?? ""
        notes = machine.notes ?? ""
    }
}

struct MaintenancePartDraft {
    var id: Int?
    var partName = ""
    var partNumber = ""
    var category = ""
    var quantityOnHand = "0"
    var reorderPoint = "0"
    var reorderQuantity = "0"
    var unitCost = "0"
    var vendorName = ""
    var binLocation = ""
    var isActive = true
    var notes = ""

    init() {}

    init(part: MaintenancePart) {
        id = part.id
        partName = part.partName
        partNumber = part.partNumber ?? ""
        category = part.category ?? ""
        quantityOnHand = part.quantityOnHand.maintenanceNumberText
        reorderPoint = part.reorderPoint.maintenanceNumberText
        reorderQuantity = part.reorderQuantity.maintenanceNumberText
        unitCost = part.unitCost.map { NSDecimalNumber(decimal: $0).stringValue } ?? "0"
        vendorName = part.vendorName ?? ""
        binLocation = part.binLocation ?? ""
        isActive = part.isActive
        notes = part.notes ?? ""
    }
}

struct MaintenanceMachineWritePayload: Encodable {
    let machineName: String
    let assetTag: String?
    let serialNumber: String?
    let manufacturer: String?
    let model: String?
    let machineType: String?
    let locationId: Int?
    let status: String
    let purchaseDate: String?
    let warrantyExpirationDate: String?
    let lastServiceDate: String?
    let nextServiceDate: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case machineName = "machine_name"
        case assetTag = "asset_tag"
        case serialNumber = "serial_number"
        case manufacturer
        case model
        case machineType = "machine_type"
        case locationId = "location_id"
        case status
        case purchaseDate = "purchase_date"
        case warrantyExpirationDate = "warranty_expiration_date"
        case lastServiceDate = "last_service_date"
        case nextServiceDate = "next_service_date"
        case notes
    }
}

struct MaintenancePartWritePayload: Encodable {
    let partName: String
    let partNumber: String?
    let category: String?
    let quantityOnHand: Int
    let reorderPoint: Int
    let reorderQuantity: Int
    let unitCost: Decimal
    let vendorName: String?
    let binLocation: String?
    let isActive: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case partName = "part_name"
        case partNumber = "part_number"
        case category
        case quantityOnHand = "quantity_on_hand"
        case reorderPoint = "reorder_point"
        case reorderQuantity = "reorder_quantity"
        case unitCost = "unit_cost"
        case vendorName = "vendor_name"
        case binLocation = "bin_location"
        case isActive = "is_active"
        case notes
    }
}

struct MaintenanceMachinePartWritePayload: Encodable {
    let machineId: Int
    let partId: Int
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case machineId = "machine_id"
        case partId = "part_id"
        case notes
    }
}

extension Decimal {
    var maintenanceNumberText: String {
        let number = NSDecimalNumber(decimal: self)
        if number.doubleValue.rounded() == number.doubleValue {
            return String(format: "%.0f", number.doubleValue)
        }
        return number.stringValue
    }
}

extension String {
    var maintenanceDisplayText: String {
        replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let decimal = try decodeIfPresent(Decimal.self, forKey: key) {
            return decimal
        }

        if let int = try decodeIfPresent(Int.self, forKey: key) {
            return Decimal(int)
        }

        if let double = try decodeIfPresent(Double.self, forKey: key) {
            return Decimal(double)
        }

        if let string = try decodeIfPresent(String.self, forKey: key) {
            return Decimal(string: string)
        }

        return nil
    }
}
