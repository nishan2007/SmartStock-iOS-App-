//
//  AppUser.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import Foundation

struct AppUser: Decodable, Identifiable {
    let id: Int
    let fullName: String
    let username: String
    let email: String?
    let roleId: Int?
    let mobilePermissions: Set<MobilePermission>

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case fullName = "full_name"
        case username
        case email
        case roleId = "role_id"
    }

    init(
        id: Int,
        fullName: String,
        username: String,
        email: String?,
        roleId: Int?,
        mobilePermissions: Set<MobilePermission> = []
    ) {
        self.id = id
        self.fullName = fullName
        self.username = username
        self.email = email
        self.roleId = roleId
        self.mobilePermissions = mobilePermissions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        fullName = try container.decode(String.self, forKey: .fullName)
        username = try container.decode(String.self, forKey: .username)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        roleId = try container.decodeIfPresent(Int.self, forKey: .roleId)
        mobilePermissions = []
    }

    func withMobilePermissions(_ permissions: Set<MobilePermission>) -> AppUser {
        AppUser(
            id: id,
            fullName: fullName,
            username: username,
            email: email,
            roleId: roleId,
            mobilePermissions: permissions
        )
    }

    func canAccess(_ permission: MobilePermission) -> Bool {
        mobilePermissions.contains(permission)
    }
}
