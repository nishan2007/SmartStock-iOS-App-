import Foundation
import Supabase

final class OverrideApprovalService {
    private let client = supabase

    func validateApprover(identifier: String, password: String, requiredPermission: MobilePermission) async throws -> AppUser {
        let trimmedIdentifier = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIdentifier.isEmpty else {
            throw OverrideApprovalError.identifierRequired
        }
        guard !trimmedPassword.isEmpty else {
            throw OverrideApprovalError.passwordRequired
        }

        let users: [OverrideLookupUser] = try await client
            .from("users")
            .select("user_id, full_name, username, email, role_id, is_active")
            .or("username.eq.\(trimmedIdentifier),email.eq.\(trimmedIdentifier),badge_id.eq.\(trimmedIdentifier)")
            .limit(5)
            .execute()
            .value

        let matched = users.first {
            $0.isActive && (
                $0.username.caseInsensitiveCompare(trimmedIdentifier) == .orderedSame
                || ($0.email?.caseInsensitiveCompare(trimmedIdentifier) == .orderedSame)
            )
        }

        guard let matched else {
            throw OverrideApprovalError.userNotFound
        }
        guard let email = matched.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else {
            throw OverrideApprovalError.userMissingEmail
        }
        guard try await authenticateWithSupabase(email: email, password: trimmedPassword) else {
            throw OverrideApprovalError.invalidCredentials
        }

        guard let roleId = matched.roleId else {
            throw OverrideApprovalError.userMissingRole
        }

        let permissions = try await RoleService.shared.fetchMobilePermissions(roleId: roleId)
        guard permissions.contains(requiredPermission) else {
            throw OverrideApprovalError.permissionMissing(requiredPermission.title)
        }

        return AppUser(
            id: matched.userId,
            fullName: matched.fullName,
            username: matched.username,
            email: matched.email,
            roleId: matched.roleId,
            mobilePermissions: permissions
        )
    }

    private func authenticateWithSupabase(email: String, password: String) async throws -> Bool {
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let url = components?.url else {
            throw OverrideApprovalError.authVerificationFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(PasswordAuthRequest(email: email, password: password))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OverrideApprovalError.authVerificationFailed
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            return false
        }

        let payload = try JSONDecoder().decode(PasswordAuthResponse.self, from: data)
        return !(payload.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

private struct OverrideLookupUser: Decodable {
    let userId: Int
    let fullName: String
    let username: String
    let email: String?
    let roleId: Int?
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case fullName = "full_name"
        case username
        case email
        case roleId = "role_id"
        case isActive = "is_active"
    }
}

enum OverrideApprovalError: LocalizedError {
    case identifierRequired
    case passwordRequired
    case userNotFound
    case userMissingEmail
    case invalidCredentials
    case userMissingRole
    case permissionMissing(String)
    case authVerificationFailed

    var errorDescription: String? {
        switch self {
        case .identifierRequired:
            return "Enter approver username, email, or badge ID."
        case .passwordRequired:
            return "Approver password is required."
        case .userNotFound:
            return "Approver account was not found or is inactive."
        case .userMissingEmail:
            return "Approver account is missing an email for credential verification."
        case .invalidCredentials:
            return "Invalid approver credentials."
        case .userMissingRole:
            return "Approver does not have a valid role."
        case .permissionMissing(let permissionTitle):
            return "Approver is missing \(permissionTitle) permission."
        case .authVerificationFailed:
            return "Unable to verify approver credentials right now."
        }
    }
}

private struct PasswordAuthRequest: Encodable {
    let email: String
    let password: String
}

private struct PasswordAuthResponse: Decodable {
    let accessToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}
