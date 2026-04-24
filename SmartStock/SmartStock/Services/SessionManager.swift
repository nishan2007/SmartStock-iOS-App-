//
//  SessionManager.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//


import Foundation
import Supabase
import Combine
import SwiftUI

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
    private enum StorageKey {
        static let allowsPersistentLogin = "smartstock.cachedDeviceApproval"
        static let pendingSharedDeviceLogout = "smartstock.pendingSharedDeviceLogout"
        static let trackedDeviceSessionId = "smartstock.trackedDeviceSessionId"
    }

    private let defaults: UserDefaults

    @Published var currentUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedStore: Store? {
        didSet {
            guard oldValue?.id != selectedStore?.id else { return }

            Task {
                await synchronizeTrackedDeviceStore()
            }
        }
    }
    @Published var availableStores: [Store] = []
    @Published private(set) var currentDevice: TrackedDevice?
    @Published private(set) var allowsPersistentLogin: Bool
    @Published private(set) var currentDeviceSessionId: Int64?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.allowsPersistentLogin = defaults.bool(forKey: StorageKey.allowsPersistentLogin)
        let storedSessionId = defaults.object(forKey: StorageKey.trackedDeviceSessionId) as? NSNumber
        self.currentDeviceSessionId = storedSessionId?.int64Value
    }

    var canManagePersistentLoginApproval: Bool {
        currentUser?.canAccess(.deviceManagement) == true
    }

    var canManageDeviceReceiptSettings: Bool {
        currentUser?.canAccess(.localDeviceSettings) == true
    }

    func restoreSession() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        if shouldClearStoredSessionBeforeRestore {
            await endTrackedDeviceSessionIfNeeded()

            do {
                try await supabase.auth.signOut()
            } catch {
                // Ignore sign-out failures here and continue loading fresh login state.
            }

            clearPendingSharedDeviceLogout()
            resetSessionState()
            return
        }

        do {
            _ = try await supabase.auth.session
            try await loadCurrentAppUser()
            try await registerTrackedDevice()
        } catch {
            resetSessionState()
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

            try await registerTrackedDevice()
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

        await endTrackedDeviceSessionIfNeeded()
        clearPendingSharedDeviceLogout()
        resetSessionState()
    }

    func handleTrackedDeviceUpdate(_ device: TrackedDevice) {
        guard device.installationId == DeviceService.shared.currentInstallationId() else { return }

        applyTrackedDevice(device)

        if device.isBlocked {
            Task {
                errorMessage = "This device has been blocked."
                await signOut()
            }
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .active:
            if !allowsPersistentLogin {
                clearPendingSharedDeviceLogout()
            }

            Task {
                await refreshCurrentDeviceAccess()
            }
        case .background:
            guard currentUser != nil, !allowsPersistentLogin else { return }
            defaults.set(true, forKey: StorageKey.pendingSharedDeviceLogout)
        case .inactive:
            break
        @unknown default:
            break
        }
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

        guard let user = users.first else {
            currentUser = nil
            return
        }

        if let roleId = user.roleId {
            let permissions = try await RoleService.shared.fetchMobilePermissions(roleId: roleId)
            currentUser = user.withMobilePermissions(permissions)
        } else {
            currentUser = user
        }
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

    private func registerTrackedDevice() async throws {
        guard let user = currentUser else { return }

        let result = try await DeviceService.shared.registerCurrentDevice(
            userId: user.id,
            storeId: selectedStore?.id
        )

        applyTrackedDevice(result.device)
        setTrackedDeviceSessionId(result.sessionId)
    }

    private func synchronizeTrackedDeviceStore() async {
        guard let user = currentUser,
              let currentDevice else { return }

        do {
            let updatedDevice = try await DeviceService.shared.updateCurrentDevice(
                deviceId: currentDevice.id,
                userId: user.id,
                storeId: selectedStore?.id
            )
            applyTrackedDevice(updatedDevice)

            if let currentDeviceSessionId {
                try await DeviceService.shared.updateDeviceSession(
                    sessionId: currentDeviceSessionId,
                    storeId: selectedStore?.id
                )
            }
        } catch {
            print("DEVICE STORE SYNC ERROR:", error)
        }
    }

    private func refreshCurrentDeviceAccess() async {
        guard currentUser != nil else { return }

        do {
            guard let device = try await DeviceService.shared.fetchCurrentDevice() else { return }
            handleTrackedDeviceUpdate(device)
        } catch {
            print("DEVICE ACCESS REFRESH ERROR:", error)
        }
    }

    private var shouldClearStoredSessionBeforeRestore: Bool {
        !allowsPersistentLogin && defaults.bool(forKey: StorageKey.pendingSharedDeviceLogout)
    }

    private func clearPendingSharedDeviceLogout() {
        defaults.removeObject(forKey: StorageKey.pendingSharedDeviceLogout)
    }

    private func resetSessionState() {
        currentUser = nil
        selectedStore = nil
        availableStores = []
        currentDevice = nil
        allowsPersistentLogin = defaults.bool(forKey: StorageKey.allowsPersistentLogin)
        setTrackedDeviceSessionId(nil)
    }

    private func applyTrackedDevice(_ device: TrackedDevice) {
        currentDevice = device
        allowsPersistentLogin = device.isApproved
        defaults.set(device.isApproved, forKey: StorageKey.allowsPersistentLogin)

        if device.isApproved {
            clearPendingSharedDeviceLogout()
        }
    }

    private func setTrackedDeviceSessionId(_ sessionId: Int64?) {
        currentDeviceSessionId = sessionId

        if let sessionId {
            defaults.set(NSNumber(value: sessionId), forKey: StorageKey.trackedDeviceSessionId)
        } else {
            defaults.removeObject(forKey: StorageKey.trackedDeviceSessionId)
        }
    }

    private func endTrackedDeviceSessionIfNeeded() async {
        guard let currentDeviceSessionId else { return }

        do {
            try await DeviceService.shared.endDeviceSession(sessionId: currentDeviceSessionId)
        } catch {
            print("END DEVICE SESSION ERROR:", error)
        }

        setTrackedDeviceSessionId(nil)
    }
}
