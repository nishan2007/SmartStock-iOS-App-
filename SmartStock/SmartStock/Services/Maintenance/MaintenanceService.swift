//
//  MaintenanceService.swift
//  SmartStock
//

import Foundation
import Supabase

enum MaintenanceServiceError: LocalizedError {
    case machineNameRequired
    case partNameRequired
    case issueSummaryRequired
    case locationRequired
    case invalidNumber(String)

    var errorDescription: String? {
        switch self {
        case .machineNameRequired:
            return "Machine name is required."
        case .partNameRequired:
            return "Part name is required."
        case .issueSummaryRequired:
            return "Describe the issue or help request."
        case .locationRequired:
            return "Select a store for this machine."
        case .invalidNumber(let field):
            return "\(field) must be a valid number."
        }
    }
}

final class MaintenanceService {
    static let shared = MaintenanceService()

    private init() {}

    func fetchMachines() async throws -> [MaintenanceMachine] {
        try await supabase
            .from("maintenance_machines")
            .select(
                """
                machine_id,
                machine_name,
                asset_tag,
                serial_number,
                manufacturer,
                model,
                machine_type,
                location_id,
                location_name,
                status,
                purchase_date,
                warranty_expiration_date,
                last_service_date,
                next_service_date,
                notes,
                created_at,
                updated_at,
                locations(name)
                """
            )
            .order("machine_name", ascending: true)
            .execute()
            .value
    }

    func fetchIssueMachines() async throws -> [MaintenanceMachine] {
        try await supabase
            .from("maintenance_machines")
            .select(
                """
                machine_id,
                machine_name,
                asset_tag,
                machine_type,
                location_id,
                location_name,
                status,
                locations(name)
                """
            )
            .neq("status", value: MaintenanceMachineStatus.retired.rawValue)
            .order("machine_name", ascending: true)
            .execute()
            .value
    }

    func fetchMachine(id: Int) async throws -> MaintenanceMachine? {
        let rows: [MaintenanceMachine] = try await supabase
            .from("maintenance_machines")
            .select(
                """
                machine_id,
                machine_name,
                asset_tag,
                serial_number,
                manufacturer,
                model,
                machine_type,
                location_id,
                location_name,
                status,
                purchase_date,
                warranty_expiration_date,
                last_service_date,
                next_service_date,
                notes,
                created_at,
                updated_at,
                locations(name)
                """
            )
            .eq("machine_id", value: id)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func fetchParts(activeOnly: Bool = false) async throws -> [MaintenancePart] {
        if activeOnly {
            return try await supabase
                .from("maintenance_parts")
                .select(partsSelect)
                .eq("is_active", value: true)
                .order("part_name", ascending: true)
                .execute()
                .value
        }

        return try await supabase
            .from("maintenance_parts")
            .select(partsSelect)
            .order("part_name", ascending: true)
            .execute()
            .value
    }

    func fetchMachineParts(machineId: Int) async throws -> [MaintenanceMachinePart] {
        try await supabase
            .from("maintenance_machine_parts")
            .select(
                """
                machine_part_id,
                machine_id,
                part_id,
                notes,
                created_at,
                updated_at,
                maintenance_parts(part_id, part_name, part_number)
                """
            )
            .eq("machine_id", value: machineId)
            .order("created_at", ascending: true)
            .execute()
            .value
    }

    func fetchLogs() async throws -> [MaintenanceLog] {
        try await supabase
            .from("maintenance_logs")
            .select("*")
            .order("service_date", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func fetchLogs(machineId: Int) async throws -> [MaintenanceLog] {
        try await supabase
            .from("maintenance_logs")
            .select("*")
            .eq("machine_id", value: machineId)
            .order("service_date", ascending: false)
            .execute()
            .value
    }

    func fetchTickets() async throws -> [MaintenanceTicket] {
        try await supabase
            .from("maintenance_tickets")
            .select(ticketSelect)
            .order("opened_at", ascending: false)
            .limit(100)
            .execute()
            .value
    }

    func fetchTicketHistory() async throws -> [MaintenanceTicket] {
        try await supabase
            .from("maintenance_tickets")
            .select(ticketSelect)
            .in("status", values: [
                MaintenanceTicketStatus.resolved.rawValue,
                MaintenanceTicketStatus.closed.rawValue,
                MaintenanceTicketStatus.canceled.rawValue
            ])
            .order("updated_at", ascending: false)
            .execute()
            .value
    }

    func fetchTicket(id: Int) async throws -> MaintenanceTicket? {
        let rows: [MaintenanceTicket] = try await supabase
            .from("maintenance_tickets")
            .select(ticketSelect)
            .eq("ticket_id", value: id)
            .limit(1)
            .execute()
            .value

        return rows.first
    }

    func fetchTickets(machineId: Int) async throws -> [MaintenanceTicket] {
        try await supabase
            .from("maintenance_tickets")
            .select(ticketSelect)
            .eq("machine_id", value: machineId)
            .order("opened_at", ascending: false)
            .execute()
            .value
    }

    func fetchTickets(openedByUserId: Int) async throws -> [MaintenanceTicket] {
        try await supabase
            .from("maintenance_tickets")
            .select(ticketSelect)
            .eq("opened_by_user_id", value: openedByUserId)
            .order("opened_at", ascending: false)
            .execute()
            .value
    }

    func createMachine(from draft: MaintenanceMachineDraft) async throws -> MaintenanceMachine {
        let payload = try machinePayload(from: draft)

        return try await supabase
            .from("maintenance_machines")
            .insert(payload)
            .select(
                """
                machine_id,
                machine_name,
                asset_tag,
                serial_number,
                manufacturer,
                model,
                machine_type,
                location_id,
                location_name,
                status,
                purchase_date,
                warranty_expiration_date,
                last_service_date,
                next_service_date,
                notes,
                created_at,
                updated_at,
                locations(name)
                """
            )
            .single()
            .execute()
            .value
    }

    func updateMachine(id: Int, draft: MaintenanceMachineDraft) async throws {
        let payload = try machinePayload(from: draft)

        try await supabase
            .from("maintenance_machines")
            .update(payload)
            .eq("machine_id", value: id)
            .execute()
    }

    func deleteMachine(id: Int) async throws {
        try await supabase
            .from("maintenance_machines")
            .delete()
            .eq("machine_id", value: id)
            .execute()
    }

    func createPart(from draft: MaintenancePartDraft) async throws {
        let payload = try partPayload(from: draft)

        try await supabase
            .from("maintenance_parts")
            .insert(payload)
            .execute()
    }

    func updatePart(id: Int, draft: MaintenancePartDraft) async throws {
        let payload = try partPayload(from: draft)

        try await supabase
            .from("maintenance_parts")
            .update(payload)
            .eq("part_id", value: id)
            .execute()
    }

    func deletePart(id: Int) async throws {
        try await supabase
            .from("maintenance_parts")
            .delete()
            .eq("part_id", value: id)
            .execute()
    }

    func addPart(machineId: Int, partId: Int, notes: String?) async throws {
        let payload = MaintenanceMachinePartWritePayload(
            machineId: machineId,
            partId: partId,
            notes: normalizedValue(notes ?? "")
        )

        try await supabase
            .from("maintenance_machine_parts")
            .upsert(payload, onConflict: "machine_id,part_id")
            .execute()
    }

    func removeMachinePart(id: Int) async throws {
        try await supabase
            .from("maintenance_machine_parts")
            .delete()
            .eq("machine_part_id", value: id)
            .execute()
    }

    func createIssueTicket(draft: MaintenanceIssueDraft, user: AppUser?) async throws {
        let summary = draft.problemSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else {
            throw MaintenanceServiceError.issueSummaryRequired
        }

        let payload = MaintenanceTicketWritePayload(
            machineId: draft.machineId,
            openedByUserId: user?.id,
            priority: draft.priority.rawValue,
            status: "OPEN",
            problemSummary: summary,
            notes: normalizedValue(draft.notes)
        )

        try await supabase
            .from("maintenance_tickets")
            .insert(payload)
            .execute()
    }

    func updateTicketStatus(
        ticketId: Int,
        status: MaintenanceTicketStatus,
        resolutionSummary: String? = nil
    ) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let payload = MaintenanceTicketStatusUpdatePayload(
            status: status.rawValue,
            resolutionSummary: normalizedValue(resolutionSummary ?? ""),
            resolvedAt: status == .resolved ? now : nil,
            closedAt: status == .closed || status == .canceled ? now : nil
        )

        try await supabase
            .from("maintenance_tickets")
            .update(payload)
            .eq("ticket_id", value: ticketId)
            .execute()
    }

    func assignTicket(ticketId: Int, technicianName: String?) async throws {
        try await supabase
            .from("maintenance_tickets")
            .update(MaintenanceTicketAssignmentPayload(assignedToName: normalizedValue(technicianName ?? "")))
            .eq("ticket_id", value: ticketId)
            .execute()
    }

    private func machinePayload(from draft: MaintenanceMachineDraft) throws -> MaintenanceMachineWritePayload {
        let machineName = draft.machineName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !machineName.isEmpty else {
            throw MaintenanceServiceError.machineNameRequired
        }

        guard draft.locationId != nil else {
            throw MaintenanceServiceError.locationRequired
        }

        return MaintenanceMachineWritePayload(
            machineName: machineName,
            assetTag: normalizedValue(draft.assetTag),
            serialNumber: normalizedValue(draft.serialNumber),
            manufacturer: normalizedValue(draft.manufacturer),
            model: normalizedValue(draft.model),
            machineType: normalizedValue(draft.machineType),
            locationId: draft.locationId,
            status: draft.status.rawValue,
            purchaseDate: normalizedValue(draft.purchaseDate),
            warrantyExpirationDate: normalizedValue(draft.warrantyExpirationDate),
            lastServiceDate: normalizedValue(draft.lastServiceDate),
            nextServiceDate: normalizedValue(draft.nextServiceDate),
            notes: normalizedValue(draft.notes)
        )
    }

    private var partsSelect: String {
        """
        part_id,
        part_name,
        part_number,
        category,
        quantity_on_hand,
        reorder_point,
        reorder_quantity,
        unit_cost,
        vendor_name,
        bin_location,
        is_active,
        notes,
        created_at,
        updated_at
        """
    }

    private var ticketSelect: String {
        """
        ticket_id,
        machine_id,
        opened_at,
        opened_by_user_id,
        priority,
        status,
        assigned_to_name,
        due_date,
        problem_summary,
        resolution_summary,
        notes,
        resolved_at,
        closed_at,
        updated_at,
        users(full_name)
        """
    }

    private func partPayload(from draft: MaintenancePartDraft) throws -> MaintenancePartWritePayload {
        let partName = draft.partName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partName.isEmpty else {
            throw MaintenanceServiceError.partNameRequired
        }

        return MaintenancePartWritePayload(
            partName: partName,
            partNumber: normalizedValue(draft.partNumber),
            category: normalizedValue(draft.category),
            quantityOnHand: try intValue(draft.quantityOnHand, field: "On hand quantity"),
            reorderPoint: try intValue(draft.reorderPoint, field: "Reorder point"),
            reorderQuantity: try intValue(draft.reorderQuantity, field: "Reorder quantity"),
            unitCost: try decimalValue(draft.unitCost, field: "Unit cost"),
            vendorName: normalizedValue(draft.vendorName),
            binLocation: normalizedValue(draft.binLocation),
            isActive: draft.isActive,
            notes: normalizedValue(draft.notes)
        )
    }

    private func intValue(_ value: String, field: String) throws -> Int {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(trimmed) else {
            throw MaintenanceServiceError.invalidNumber(field)
        }
        return number
    }

    private func decimalValue(_ value: String, field: String) throws -> Decimal {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Decimal(string: trimmed) else {
            throw MaintenanceServiceError.invalidNumber(field)
        }
        return number
    }
}
