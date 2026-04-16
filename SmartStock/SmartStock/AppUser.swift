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

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case fullName = "full_name"
        case username
        case email
        case roleId = "role_id"
    }
}
