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
            // Step 1: find email from username
            let results: [EmailLookupResult] = try await supabase
                .from("users")
                .select("email")
                .ilike("username", pattern: username)
                .limit(1)
                .execute()
                .value

            guard let email = results.first?.email,
                  !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "User not found"
                return false
            }

            // Step 2: login using email
            try await supabase.auth.signIn(
                email: email,
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
