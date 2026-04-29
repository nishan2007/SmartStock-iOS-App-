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
    private let encoder = JSONEncoder()

    private init() {}

    func fetchEmployees() async throws -> [Employee] {
        let response = try await client
            .from("users")
            .select("""
                user_id,
                username,
                first_name,
                middle_name,
                last_name,
                full_name,
                email,
                phone,
                badge_id,
                compensation_type,
                salary,
                role_id,
                auth_user_id,
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
        firstName: String,
        middleName: String?,
        lastName: String,
        fullName: String,
        email: String?,
        phone: String?,
        badgeId: String?,
        compensationType: String?,
        salary: Decimal?,
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

        let authResponse: CreateEmployeeAuthUserResponse = try await callEdgeFunction(
            "create-employee-auth-user",
            body: CreateEmployeeAuthUserRequest(
                email: normalizedEmail,
                password: normalizedPassword,
                fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                isActive: isActive
            )
        )

        do {
            let insertPayload = UserInsertDTO(
                auth_user_id: authResponse.userId,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                first_name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                middle_name: emptyToNil(middleName),
                last_name: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                full_name: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: normalizedEmail,
                phone: emptyToNil(phone),
                badge_id: emptyToNil(badgeId),
                compensation_type: emptyToNil(compensationType),
                salary: salary,
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
            _ = try? await callEdgeFunction(
                "delete-employee-auth-user",
                method: "DELETE",
                body: DeleteEmployeeAuthUserRequest(userId: authResponse.userId)
            ) as EmptyFunctionResponse

            throw EmployeeServiceError.createEmployeeFailed(underlying: error)
        }
    }

    func updateEmployee(
        employee: Employee,
        username: String,
        firstName: String,
        middleName: String?,
        lastName: String,
        fullName: String,
        email: String?,
        phone: String?,
        badgeId: String?,
        compensationType: String?,
        salary: Decimal?,
        password: String?,
        roleId: Int,
        isActive: Bool
    ) async throws {
        let normalizedEmail = emptyToNil(email)
        guard normalizedEmail != nil else {
            throw EmployeeServiceError.emailRequiredForAuthUser
        }

        let trimmedFullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        var authUserId = emptyToNil(employee.authUserId)
        let authFieldsChanged = normalizedEmail != emptyToNil(employee.email)
            || trimmedFullName != employee.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            || isActive != employee.isActive
            || trimmedPassword?.isEmpty == false

        if authFieldsChanged {
            if let existingAuthUserId = authUserId {
                do {
                    _ = try await callEdgeFunction(
                        "update-employee-auth-user",
                        body: UpdateEmployeeAuthUserRequest(
                            userId: existingAuthUserId,
                            email: normalizedEmail,
                            password: trimmedPassword,
                            fullName: trimmedFullName,
                            isActive: isActive
                        )
                    ) as EmptyFunctionResponse
                } catch EmployeeServiceError.authUserNotFound {
                    guard let trimmedPassword, !trimmedPassword.isEmpty else {
                        throw EmployeeServiceError.passwordRequiredToRelinkAuthUser
                    }

                    let authResponse: CreateEmployeeAuthUserResponse = try await callEdgeFunction(
                        "create-employee-auth-user",
                        body: CreateEmployeeAuthUserRequest(
                            email: normalizedEmail!,
                            password: trimmedPassword,
                            fullName: trimmedFullName,
                            isActive: isActive
                        )
                    )
                    authUserId = authResponse.userId
                }
            } else {
                guard let trimmedPassword, !trimmedPassword.isEmpty else {
                    throw EmployeeServiceError.passwordRequiredToRelinkAuthUser
                }

                let authResponse: CreateEmployeeAuthUserResponse = try await callEdgeFunction(
                    "create-employee-auth-user",
                    body: CreateEmployeeAuthUserRequest(
                        email: normalizedEmail!,
                        password: trimmedPassword,
                        fullName: trimmedFullName,
                        isActive: isActive
                    )
                )
                authUserId = authResponse.userId
            }
        }

        let updatePayload = UserUpdateDTO(
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            first_name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            middle_name: emptyToNil(middleName),
            last_name: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            full_name: trimmedFullName,
            email: normalizedEmail,
            phone: emptyToNil(phone),
            badge_id: emptyToNil(badgeId),
            compensation_type: emptyToNil(compensationType),
            salary: salary,
            password_hash: nil,
            role_id: roleId,
            auth_user_id: authUserId,
            is_active: isActive
        )

        _ = try await client
            .from("users")
            .update(updatePayload)
            .eq("user_id", value: employee.id)
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

    func fetchEmployeeStores(employeeId: Int) async throws -> [Store] {
        let rows: [EmployeeStoreAssignmentRow] = try await client
            .from("user_locations")
            .select("location_id, locations!user_locations_location_id_fkey(location_id, name, address, created_at)")
            .eq("user_id", value: employeeId)
            .execute()
            .value

        return rows.map { row in
            row.locations ?? Store(id: row.location_id, name: "Store #\(row.location_id)", address: nil, createdAt: nil)
        }
    }

    func toggleEmployeeActive(employeeId: Int, isActive: Bool) async throws {
        let authLookup: [AuthUserLookupDTO] = try await client
            .from("users")
            .select("auth_user_id, email, full_name")
            .eq("user_id", value: employeeId)
            .limit(1)
            .execute()
            .value

        if let authUser = authLookup.first,
           let authUserId = emptyToNil(authUser.auth_user_id) {
            do {
                _ = try await callEdgeFunction(
                    "update-employee-auth-user",
                    body: UpdateEmployeeAuthUserRequest(
                        userId: authUserId,
                        email: emptyToNil(authUser.email),
                        password: nil,
                        fullName: authUser.full_name ?? "",
                        isActive: isActive
                    )
                ) as EmptyFunctionResponse
            } catch EmployeeServiceError.authUserNotFound {
                throw EmployeeServiceError.passwordRequiredToRelinkAuthUser
            }
        }

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
            _ = try await callEdgeFunction(
                "delete-employee-auth-user",
                method: "DELETE",
                body: DeleteEmployeeAuthUserRequest(userId: authUserId)
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

    private func callEdgeFunction<Response: Decodable, Body: Encodable>(
        _ name: String,
        method: String = "POST",
        body: Body
    ) async throws -> Response {
        let session = try await client.auth.session
        let url = supabaseURL
            .appendingPathComponent("functions")
            .appendingPathComponent("v1")
            .appendingPathComponent(name)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmployeeServiceError.invalidFunctionResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = functionErrorMessage(from: data)
            if message.localizedCaseInsensitiveContains("User not found") {
                throw EmployeeServiceError.authUserNotFound
            }
            throw EmployeeServiceError.edgeFunctionFailed(message)
        }

        if Response.self == EmptyFunctionResponse.self {
            return EmptyFunctionResponse() as! Response
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw EmployeeServiceError.edgeFunctionFailed("The \(name) function returned an unexpected response.")
        }
    }

    private func functionErrorMessage(from data: Data) -> String {
        guard !data.isEmpty else { return "The employee auth request failed." }

        if let errorResponse = try? decoder.decode(EdgeFunctionErrorResponse.self, from: data) {
            return errorResponse.message
                ?? errorResponse.error
                ?? errorResponse.msg
                ?? "The employee auth request failed."
        }

        return String(data: data, encoding: .utf8) ?? "The employee auth request failed."
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
    case passwordRequiredToRelinkAuthUser
    case authUserNotFound
    case invalidFunctionResponse
    case edgeFunctionFailed(String)
    case createEmployeeFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .emailRequiredForAuthUser:
            return "Email is required for new employees so a login can be created."
        case .passwordRequiredForAuthUser:
            return "Password is required for new employees so a login can be created."
        case .passwordRequiredToRelinkAuthUser:
            return "The linked Supabase Auth user was not found. Enter a new password to recreate the login."
        case .authUserNotFound:
            return "User not found."
        case .invalidFunctionResponse:
            return "The employee auth function returned an invalid response."
        case .edgeFunctionFailed(let message):
            return message
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
    let first_name: String
    let middle_name: String?
    let last_name: String
    let full_name: String
    let email: String?
    let phone: String?
    let badge_id: String?
    let compensation_type: String?
    let salary: Decimal?
    let password_hash: String?
    let role_id: Int
    let is_active: Bool
}

private struct UserUpdateDTO: Encodable {
    let username: String
    let first_name: String
    let middle_name: String?
    let last_name: String
    let full_name: String
    let email: String?
    let phone: String?
    let badge_id: String?
    let compensation_type: String?
    let salary: Decimal?
    let password_hash: String?
    let role_id: Int
    let auth_user_id: String?
    let is_active: Bool
}

private struct CreateEmployeeAuthUserRequest: Encodable {
    let email: String
    let password: String
    let full_name: String
    let is_active: Bool

    init(email: String, password: String, fullName: String, isActive: Bool) {
        self.email = email
        self.password = password
        self.full_name = fullName
        self.is_active = isActive
    }
}

private struct CreateEmployeeAuthUserResponse: Decodable {
    let userId: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let userId = try container.decodeIfPresent(String.self, forKey: .userId) {
            self.userId = userId
        } else {
            self.userId = try container.decode(String.self, forKey: .id)
        }
    }
}

private struct UpdateEmployeeAuthUserRequest: Encodable {
    let user_id: String
    let email: String?
    let password: String?
    let full_name: String
    let is_active: Bool

    init(userId: String, email: String?, password: String?, fullName: String, isActive: Bool) {
        self.user_id = userId
        self.email = email
        self.password = password?.isEmpty == false ? password : nil
        self.full_name = fullName
        self.is_active = isActive
    }
}

private struct DeleteEmployeeAuthUserRequest: Encodable {
    let user_id: String

    init(userId: String) {
        self.user_id = userId
    }
}

private struct EmptyFunctionResponse: Decodable {}

private struct EdgeFunctionErrorResponse: Decodable {
    let error: String?
    let message: String?
    let msg: String?
}

private struct AuthUserLookupDTO: Decodable {
    let auth_user_id: String?
    let email: String?
    let full_name: String?
}

private struct UserLocationInsertDTO: Encodable {
    let user_id: Int
    let location_id: Int
}

private struct EmployeeRowDTO: Decodable {
    let user_id: Int
    let username: String
    let first_name: String?
    let middle_name: String?
    let last_name: String?
    let full_name: String
    let email: String?
    let phone: String?
    let badge_id: String?
    let compensation_type: String?
    let salary: Decimal?
    let role_id: Int
    let auth_user_id: String?
    let is_active: Bool?
    let created_at: String?
    let roles: [RoleRowDTO]
    let user_locations: [UserLocationRowDTO]

    enum CodingKeys: String, CodingKey {
        case user_id
        case username
        case first_name
        case middle_name
        case last_name
        case full_name
        case email
        case phone
        case badge_id
        case compensation_type
        case salary
        case role_id
        case auth_user_id
        case is_active
        case created_at
        case roles
        case user_locations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        user_id = try container.decode(Int.self, forKey: .user_id)
        username = try container.decode(String.self, forKey: .username)
        first_name = try container.decodeIfPresent(String.self, forKey: .first_name)
        middle_name = try container.decodeIfPresent(String.self, forKey: .middle_name)
        last_name = try container.decodeIfPresent(String.self, forKey: .last_name)
        full_name = try container.decode(String.self, forKey: .full_name)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        badge_id = try container.decodeIfPresent(String.self, forKey: .badge_id)
        compensation_type = try container.decodeIfPresent(String.self, forKey: .compensation_type)
        salary = try container.decodeFlexibleDecimalIfPresent(forKey: .salary)
        role_id = try container.decode(Int.self, forKey: .role_id)
        auth_user_id = try container.decodeIfPresent(String.self, forKey: .auth_user_id)
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
            firstName: first_name,
            middleName: middle_name,
            lastName: last_name,
            fullName: full_name,
            email: email,
            phone: phone,
            badgeId: badge_id,
            compensationType: compensation_type,
            salary: salary,
            roleId: role_id,
            roleName: roles.first?.role_name ?? "Unknown",
            authUserId: auth_user_id,
            isActive: is_active ?? true,
            createdAt: parsePostgresDate(created_at),
            assignedStores: user_locations.compactMap { $0.locations?.toStore() }
        )
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        if let decimal = try? decodeIfPresent(Decimal.self, forKey: key) {
            return decimal
        }

        if let double = try? decodeIfPresent(Double.self, forKey: key) {
            return Decimal(double)
        }

        if let string = try? decodeIfPresent(String.self, forKey: key),
           !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Decimal(string: string)
        }

        return nil
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
