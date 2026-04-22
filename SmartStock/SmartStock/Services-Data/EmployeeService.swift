//
//  EmployeeService.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

import Foundation
import Supabase

final class EmployeeService {
    static let shared = EmployeeService()

    private let client = supabase
    private let decoder = JSONDecoder()

    private init() {}

    func fetchEmployees() async throws -> [Employee] {
        let response = try await client
            .from("users")
            .select("""
                user_id,
                username,
                full_name,
                email,
                phone,
                role_id,
                is_active,
                created_at,
                roles!users_role_id_fkey ( role_id, role_name ),
                user_locations (
                    location_id,
                    locations!user_locations_location_id_fkey (
                        location_id,
                        name,
                        address,
                        created_at
                    )
                )
            """)
            .order("full_name", ascending: true)
            .execute()

        let rows = try decoder.decode([EmployeeRowDTO].self, from: response.data)
        return rows.map { $0.toEmployee() }
    }

    func createEmployee(
        username: String,
        fullName: String,
        email: String?,
        phone: String?,
        password: String,
        roleId: Int,
        isActive: Bool,
        storeIds: [Int]
    ) async throws {
        guard let normalizedEmail = emptyToNil(email) else {
            throw EmployeeServiceError.emailRequiredForAuthUser
        }

        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPassword.isEmpty else {
            throw EmployeeServiceError.passwordRequiredForAuthUser
        }

        let session = try await client.auth.session

        let authResponse: CreateEmployeeAuthUserResponse = try await client.functions.invoke(
            "create-employee-auth-user",
            options: FunctionInvokeOptions(
                headers: [
                    "Authorization": "Bearer \(session.accessToken)",
                    "Content-Type": "application/json"
                ],
                body: CreateEmployeeAuthUserRequest(
                    email: normalizedEmail,
                    password: normalizedPassword,
                    fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        )

        do {
            let insertPayload = UserInsertDTO(
                auth_user_id: authResponse.userId,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: normalizedEmail,
                phone: emptyToNil(phone),
                password_hash: nil,
                role_id: roleId,
                is_active: isActive
            )

            let userResponse = try await client
                .from("users")
                .insert(insertPayload)
                .select("user_id")
                .single()
                .execute()

            let createdUser = try decoder.decode(UserIdDTO.self, from: userResponse.data)

            if !storeIds.isEmpty {
                let mappings = storeIds.map {
                    UserLocationInsertDTO(user_id: createdUser.user_id, location_id: $0)
                }

                _ = try await client
                    .from("user_locations")
                    .insert(mappings)
                    .execute()
            }
        } catch {
            try? await client.functions.invoke(
                "delete-employee-auth-user",
                options: FunctionInvokeOptions(
                    method: .delete,
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)",
                        "Content-Type": "application/json"
                    ],
                    body: DeleteEmployeeAuthUserRequest(userId: authResponse.userId)
                )
            ) as EmptyFunctionResponse

            throw EmployeeServiceError.createEmployeeFailed(underlying: error)
        }
    }

    func updateEmployee(
        employeeId: Int,
        username: String,
        fullName: String,
        email: String?,
        phone: String?,
        passwordHash: String?,
        roleId: Int,
        isActive: Bool
    ) async throws {
        let updatePayload = UserUpdateDTO(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
            email: emptyToNil(email),
            phone: emptyToNil(phone),
            password_hash: nil,
            role_id: roleId,
            is_active: isActive
        )

        _ = try await client
            .from("users")
            .update(updatePayload)
            .eq("user_id", value: employeeId)
            .execute()
    }

    func updateEmployeeStores(employeeId: Int, storeIds: [Int]) async throws {
        _ = try await client
            .from("user_locations")
            .delete()
            .eq("user_id", value: employeeId)
            .execute()

        if !storeIds.isEmpty {
            let mappings = storeIds.map {
                UserLocationInsertDTO(user_id: employeeId, location_id: $0)
            }

            _ = try await client
                .from("user_locations")
                .insert(mappings)
                .execute()
        }
    }

    func toggleEmployeeActive(employeeId: Int, isActive: Bool) async throws {
        _ = try await client
            .from("users")
            .update(["is_active": isActive])
            .eq("user_id", value: employeeId)
            .execute()
    }

    func deleteEmployee(employeeId: Int) async throws {
        let authLookup: [AuthUserLookupDTO] = try await client
            .from("users")
            .select("auth_user_id")
            .eq("user_id", value: employeeId)
            .limit(1)
            .execute()
            .value

        if let authUserId = authLookup.first?.auth_user_id,
           !authUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let session = try await client.auth.session

            _ = try await client.functions.invoke(
                "delete-employee-auth-user",
                options: FunctionInvokeOptions(
                    method: .delete,
                    headers: [
                        "Authorization": "Bearer \(session.accessToken)",
                        "Content-Type": "application/json"
                    ],
                    body: DeleteEmployeeAuthUserRequest(userId: authUserId)
                )
            ) as EmptyFunctionResponse
        }

        _ = try await client
            .from("user_locations")
            .delete()
            .eq("user_id", value: employeeId)
            .execute()

        _ = try await client
            .from("users")
            .delete()
            .eq("user_id", value: employeeId)
            .execute()
    }

    private func emptyToNil(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

private func parsePostgresDate(_ value: String?) -> Date? {
    guard let value = value else { return nil }

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
        .withInternetDateTime,
        .withFractionalSeconds
    ]

    // Try with fractional seconds first
    if let date = formatter.date(from: value) {
        return date
    }

    // Fallback (sometimes Postgres omits fractional seconds)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

enum EmployeeServiceError: LocalizedError {
    case emailRequiredForAuthUser
    case passwordRequiredForAuthUser
    case createEmployeeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emailRequiredForAuthUser:
            return "Email is required for new employees so a login can be created."
        case .passwordRequiredForAuthUser:
            return "Password is required for new employees so a login can be created."
        case .createEmployeeFailed(let underlying):
            return EmployeeServiceError.message(from: underlying)
        }
    }

    private static func message(from error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           description != error.localizedDescription {
            return description
        }

        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !message.isEmpty {
            return message
        }

        return "Failed to create employee."
    }
}

// MARK: - DTOs

private struct UserIdDTO: Decodable {
    let user_id: Int
}

private struct UserInsertDTO: Encodable {
    let auth_user_id: String
    let username: String
    let full_name: String
    let email: String?
    let phone: String?
    let password_hash: String?
    let role_id: Int
    let is_active: Bool
}

private struct UserUpdateDTO: Encodable {
    let username: String
    let full_name: String
    let email: String?
    let phone: String?
    let password_hash: String?
    let role_id: Int
    let is_active: Bool
}

private struct CreateEmployeeAuthUserRequest: Encodable {
    let email: String
    let password: String
    let full_name: String

    init(email: String, password: String, fullName: String) {
        self.email = email
        self.password = password
        self.full_name = fullName
    }
}

private struct CreateEmployeeAuthUserResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

private struct DeleteEmployeeAuthUserRequest: Encodable {
    let user_id: String

    init(userId: String) {
        self.user_id = userId
    }
}

private struct EmptyFunctionResponse: Decodable {}

private struct AuthUserLookupDTO: Decodable {
    let auth_user_id: String?
}

private struct UserLocationInsertDTO: Encodable {
    let user_id: Int
    let location_id: Int
}

private struct EmployeeRowDTO: Decodable {
    let user_id: Int
    let username: String
    let full_name: String
    let email: String?
    let phone: String?
    let role_id: Int
    let is_active: Bool?
    let created_at: String?
    let roles: [RoleRowDTO]
    let user_locations: [UserLocationRowDTO]

    enum CodingKeys: String, CodingKey {
        case user_id
        case username
        case full_name
        case email
        case phone
        case role_id
        case is_active
        case created_at
        case roles
        case user_locations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        user_id = try container.decode(Int.self, forKey: .user_id)
        username = try container.decode(String.self, forKey: .username)
        full_name = try container.decode(String.self, forKey: .full_name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        role_id = try container.decode(Int.self, forKey: .role_id)
        is_active = try container.decodeIfPresent(Bool.self, forKey: .is_active)
        created_at = try container.decodeIfPresent(String.self, forKey: .created_at)

        if let roleArray = try? container.decode([RoleRowDTO].self, forKey: .roles) {
            roles = roleArray
        } else if let singleRole = try? container.decode(RoleRowDTO.self, forKey: .roles) {
            roles = [singleRole]
        } else {
            roles = []
        }

        user_locations = (try? container.decode([UserLocationRowDTO].self, forKey: .user_locations)) ?? []
    }

    func toEmployee() -> Employee {
        Employee(
            id: user_id,
            username: username,
            fullName: full_name,
            email: email,
            phone: phone,
            roleId: role_id,
            roleName: roles.first?.role_name ?? "Unknown",
            isActive: is_active ?? true,
            createdAt: parsePostgresDate(created_at),
            assignedStores: user_locations.compactMap { $0.locations?.toStore() }
        )
    }
}

private struct RoleRowDTO: Decodable {
    let role_id: Int?
    let role_name: String
}

private struct UserLocationRowDTO: Decodable {
    let location_id: Int?
    let locations: LocationRowDTO?
}

private struct LocationRowDTO: Decodable {
    let location_id: Int
    let name: String
    let address: String?
    let created_at: String?

    func toStore() -> Store {
        Store(
            id: location_id,
            name: name,
            address: address,
            createdAt: parsePostgresDate(created_at)
        )
    }
}
