//
//  CashDrawerService.swift
//  SmartStock
//

import Foundation
import Supabase

struct CashDrawerDraft {
    var drawerName: String
    var drawerCode: String
    var startingCashAmount: Decimal
    var floatMix: [Int: Int]
    var isActive: Bool
}

struct CashDrawerUpsert: Encodable {
    let location_id: Int
    let drawer_name: String
    let description: String?
    let starting_cash_amount: Decimal
    let float_mix: [String: Int]
    let is_active: Bool
}

private struct CashDrawerUpdate: Encodable {
    let drawer_name: String
    let description: String?
    let starting_cash_amount: Decimal
    let float_mix: [String: Int]
    let is_active: Bool
}

private struct CashDrawerDeactivateAssignment: Encodable {
    let is_active = false
    let unassigned_at: String
}

private struct CashDrawerAssignmentInsert: Encodable {
    let location_id: Int
    let cash_drawer_id: Int64
    let device_id: String
    let notes: String?
    let is_active = true
}

struct CashDrawerService {
    private let client = supabase

    func fetchDrawers(storeId: Int, includeInactive: Bool = true) async throws -> [CashDrawer] {
        var query = client
            .from("cash_drawers")
            .select("drawer_id:cash_drawer_id, store_id:location_id, drawer_name, drawer_code:description, starting_cash_amount, float_mix, is_active, created_at, updated_at")
            .eq("location_id", value: storeId)

        if !includeInactive {
            query = query.eq("is_active", value: true)
        }

        return try await query
            .order("is_active", ascending: false)
            .order("drawer_name", ascending: true)
            .execute()
            .value
    }

    func fetchAssignments(storeId: Int, activeOnly: Bool = true) async throws -> [CashDrawerDeviceAssignment] {
        var query = client
            .from("cash_drawer_device_assignments")
                .select("""
                assignment_id,
                drawer_id:cash_drawer_id,
                store_id:location_id,
                device_id,
                is_active,
                notes,
                assigned_at,
                unassigned_at,
                cash_drawers(drawer_id:cash_drawer_id, store_id:location_id, drawer_name, drawer_code:description, starting_cash_amount, float_mix, is_active, created_at, updated_at),
                devices(device_id, device_name, local_username, os_name, os_arch)
            """)
            .eq("location_id", value: storeId)

        if activeOnly {
            query = query.eq("is_active", value: true)
        }

        return try await query
            .order("assigned_at", ascending: false)
            .execute()
            .value
    }

    func resolveAssignedDrawer(storeId: Int, deviceId: UUID?) async throws -> ResolvedCashDrawer {
        guard let deviceId else { throw CashDrawerError.missingDevice }

        let assignments: [CashDrawerDeviceAssignment] = try await client
            .from("cash_drawer_device_assignments")
            .select("""
                assignment_id,
                drawer_id:cash_drawer_id,
                store_id:location_id,
                device_id,
                is_active,
                notes,
                assigned_at,
                unassigned_at,
                cash_drawers(drawer_id:cash_drawer_id, store_id:location_id, drawer_name, drawer_code:description, starting_cash_amount, float_mix, is_active, created_at, updated_at)
            """)
            .eq("location_id", value: storeId)
            .eq("device_id", value: deviceId.uuidString)
            .eq("is_active", value: true)
            .limit(1)
            .execute()
            .value

        guard let assignment = assignments.first,
              let drawer = assignment.cashDrawers,
              drawer.isActive else {
            throw CashDrawerError.noAssignedDrawer
        }

        return ResolvedCashDrawer(drawerId: drawer.drawerId, drawerName: drawer.displayName)
    }

    @discardableResult
    func saveDrawer(storeId: Int, draft: CashDrawerDraft, drawerId: Int64?) async throws -> CashDrawer {
        let name = draft.drawerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw NSError(domain: "CashDrawerService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a drawer name."])
        }
        let code = draft.drawerCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let floatMix = normalizedFloatMixForSave(draft.floatMix)

        if let drawerId {
            return try await client
                .from("cash_drawers")
                .update(
                    CashDrawerUpdate(
                        drawer_name: name,
                        description: code.isEmpty ? nil : code,
                        starting_cash_amount: draft.startingCashAmount,
                        float_mix: floatMix,
                        is_active: draft.isActive
                    )
                )
                .eq("cash_drawer_id", value: String(drawerId))
                .select("drawer_id:cash_drawer_id, store_id:location_id, drawer_name, drawer_code:description, starting_cash_amount, float_mix, is_active, created_at, updated_at")
                .single()
                .execute()
                .value
        }

        return try await client
            .from("cash_drawers")
            .insert(
                CashDrawerUpsert(
                    location_id: storeId,
                    drawer_name: name,
                    description: code.isEmpty ? nil : code,
                    starting_cash_amount: draft.startingCashAmount,
                    float_mix: floatMix,
                    is_active: draft.isActive
                )
            )
            .select("drawer_id:cash_drawer_id, store_id:location_id, drawer_name, drawer_code:description, starting_cash_amount, float_mix, is_active, created_at, updated_at")
            .single()
            .execute()
            .value
    }

    func assign(deviceId: UUID, to drawer: CashDrawer, storeId: Int, notes: String? = nil) async throws {
        try await unassign(deviceId: deviceId, storeId: storeId)
        _ = try await client
            .from("cash_drawer_device_assignments")
            .insert(CashDrawerAssignmentInsert(location_id: storeId, cash_drawer_id: drawer.drawerId, device_id: deviceId.uuidString, notes: normalized(notes)))
            .execute()
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func unassign(deviceId: UUID, storeId: Int) async throws {
        _ = try await client
            .from("cash_drawer_device_assignments")
            .update(CashDrawerDeactivateAssignment(unassigned_at: ISO8601DateFormatter().string(from: Date())))
            .eq("location_id", value: storeId)
            .eq("device_id", value: deviceId.uuidString)
            .eq("is_active", value: true)
            .execute()
    }

    func floatMixTotalInCents(_ mix: [Int: Int]) -> Int {
        mix.reduce(0) { partial, entry in
            guard entry.key > 0, entry.value > 0 else { return partial }
            return partial + (entry.key * entry.value)
        }
    }

    private func normalizedFloatMixForSave(_ mix: [Int: Int]) -> [String: Int] {
        var normalized: [String: Int] = [:]
        for denomination in CashDrawer.floatDenominations {
            let quantity = max(mix[denomination] ?? 0, 0)
            if quantity > 0 {
                normalized[String(denomination)] = quantity
            }
        }
        return normalized
    }
}
