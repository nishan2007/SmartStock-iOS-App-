//
//  RoleService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

import Foundation
import Supabase

final class RoleService {
    static let shared = RoleService()

    private let client = supabase
    private let decoder = JSONDecoder()

    private init() {}

    func fetchRoles() async throws -> [Role] {
        let response = try await client
            .from("roles")
            .select("role_id, role_name")
            .order("role_id", ascending: true)
            .execute()

        let rows = try decoder.decode([RoleRowDTO].self, from: response.data)

        return rows.map {
            Role(
                id: $0.role_id,
                name: $0.role_name
            )
        }
    }

    func fetchMobilePermissions(roleId: Int) async throws -> Set<MobilePermission> {
        let rows: [RoleMobilePermissionRowDTO] = try await client
            .from("role_mobile_permissions")
            .select("mobile_permissions(permission_key)")
            .eq("role_id", value: roleId)
            .execute()
            .value

        return Set(rows.compactMap { row in
            guard let key = row.mobile_permissions?.permission_key else { return nil }
            return MobilePermission(rawValue: key)
        })
    }

    func fetchMobilePermissionsByRole() async throws -> [Int: Set<MobilePermission>] {
        let rows: [RoleMobilePermissionWithRoleDTO] = try await client
            .from("role_mobile_permissions")
            .select("role_id, mobile_permissions(permission_key)")
            .execute()
            .value

        return rows.reduce(into: [:]) { result, row in
            guard let key = row.mobile_permissions?.permission_key,
                  let permission = MobilePermission(rawValue: key) else { return }

            result[row.role_id, default: []].insert(permission)
        }
    }

    func updateMobilePermissions(roleId: Int, permissions: Set<MobilePermission>) async throws {
        _ = try await client
            .from("role_mobile_permissions")
            .delete()
            .eq("role_id", value: roleId)
            .execute()

        guard !permissions.isEmpty else { return }

        let payload = permissions.map {
            RoleMobilePermissionInsertDTO(role_id: roleId, permission_key: $0.rawValue)
        }

        _ = try await client
            .from("role_mobile_permissions")
            .insert(payload)
            .execute()
    }
}

private struct RoleRowDTO: Decodable {
    let role_id: Int
    let role_name: String
}

private struct RoleMobilePermissionRowDTO: Decodable {
    let mobile_permissions: MobilePermissionRowDTO?
}

private struct RoleMobilePermissionWithRoleDTO: Decodable {
    let role_id: Int
    let mobile_permissions: MobilePermissionRowDTO?
}

private struct MobilePermissionRowDTO: Decodable {
    let permission_key: String
}

private struct RoleMobilePermissionInsertDTO: Encodable {
    let role_id: Int
    let permission_key: String
}
