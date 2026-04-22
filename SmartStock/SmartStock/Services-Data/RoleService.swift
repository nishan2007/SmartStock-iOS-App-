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
}

private struct RoleRowDTO: Decodable {
    let role_id: Int
    let role_name: String
}
