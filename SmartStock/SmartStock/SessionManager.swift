//
//  SessionManager.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//


import Foundation
import Supabase
import Combine

private struct EmailLookupResult: Decodable {
    let email: String?
    let authUserId: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case email
        case authUserId = "auth_user_id"
        case isActive = "is_active"
    }
}

@MainActor
final class SessionManager: ObservableObject {
    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedStore: Store?
    @Published var availableStores: [Store] = []

    func restoreSession() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            _ = try await supabase.auth.session
            try await loadCurrentAppUser()
        } catch {
            currentUser = nil
        }
    }

    func signIn(username: String, password: String) async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let usernameOrEmail = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = password.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !usernameOrEmail.isEmpty, !password.isEmpty else {
                errorMessage = "Enter username/email and password."
                return false
            }

            let email: String
            if usernameOrEmail.contains("@") {
                // With RLS enabled, unauthenticated users may not be able to read the users table.
                // Email login can go directly through Supabase Auth and load the profile afterward.
                email = usernameOrEmail
            } else {
                // Username login needs a pre-auth username -> email lookup. This only works if the
                // database exposes a narrow lookup policy/RPC/function for unauthenticated clients.
                let results = try await lookupLoginUser(usernameOrEmail)

                guard let matchedEmail = results.first?.email,
                      !matchedEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "User not found. Try logging in with your email address."
                    return false
                }

                if results.first?.isActive == false {
                    errorMessage = "This employee account is inactive."
                    return false
                }

                if results.first?.authUserId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    errorMessage = "This employee does not have a linked auth account yet."
                    return false
                }

                email = matchedEmail
            }

            try await supabase.auth.signIn(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )

            // Step 3: load SmartStock user
            try await loadCurrentAppUser()

            if currentUser == nil {
                errorMessage = "User not linked properly"
                try? await supabase.auth.signOut()
                return false
            }

            return true

        } catch {
            print("LOGIN ERROR:", error)
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func lookupLoginUser(_ usernameOrEmail: String) async throws -> [EmailLookupResult] {
        return try await supabase
            .rpc("lookup_login_user", params: ["identifier": usernameOrEmail])
            .execute()
            .value
    }

    func signOut() async {
        do {
            try await supabase.auth.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        currentUser = nil
    }

    private func loadCurrentAppUser() async throws {
        let session = try await supabase.auth.session
        let authUserId = session.user.id.uuidString

        let users: [AppUser] = try await supabase
            .from("users")
            .select("user_id, full_name, username, email, role_id")
            .eq("auth_user_id", value: authUserId)
            .limit(1)
            .execute()
            .value

        currentUser = users.first
    }
    
    func loadUserStores() async {
        guard let userId = currentUser?.id else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let rows: [UserLocationStoreRow] = try await supabase
                .from("user_locations")
                .select("locations(location_id, name)")
                .eq("user_id", value: userId)
                .execute()
                .value

            availableStores = rows.map { $0.locations }

            if availableStores.count == 1 {
                selectedStore = availableStores.first
            }
        } catch {
            print("LOAD STORES ERROR:", error)
            errorMessage = error.localizedDescription
        }
    }
}
