//
//  Employee.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  Employee.swift
//  SmartStock
//

import Foundation

struct Employee: Identifiable, Decodable, Hashable {
    let id: Int
    var username: String
    var fullName: String
    var email: String?
    var phone: String?
    var roleId: Int
    var roleName: String
    var isActive: Bool
    var createdAt: Date?
    var assignedStores: [Store]

    init(
        id: Int,
        username: String,
        fullName: String,
        email: String? = nil,
        phone: String? = nil,
        roleId: Int,
        roleName: String,
        isActive: Bool,
        createdAt: Date? = nil,
        assignedStores: [Store] = []
    ) {
        self.id = id
        self.username = username
        self.fullName = fullName
        self.email = email
        self.phone = phone
        self.roleId = roleId
        self.roleName = roleName
        self.isActive = isActive
        self.createdAt = createdAt
        self.assignedStores = assignedStores
    }
}
