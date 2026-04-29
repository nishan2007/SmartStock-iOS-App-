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
    var firstName: String?
    var middleName: String?
    var lastName: String?
    var fullName: String
    var email: String?
    var phone: String?
    var badgeId: String?
    var compensationType: String?
    var salary: Decimal?
    var roleId: Int
    var roleName: String
    var authUserId: String?
    var isActive: Bool
    var createdAt: Date?
    var assignedStores: [Store]

    init(
        id: Int,
        username: String,
        firstName: String? = nil,
        middleName: String? = nil,
        lastName: String? = nil,
        fullName: String,
        email: String? = nil,
        phone: String? = nil,
        badgeId: String? = nil,
        compensationType: String? = nil,
        salary: Decimal? = nil,
        roleId: Int,
        roleName: String,
        authUserId: String? = nil,
        isActive: Bool,
        createdAt: Date? = nil,
        assignedStores: [Store] = []
    ) {
        self.id = id
        self.username = username
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.fullName = fullName
        self.email = email
        self.phone = phone
        self.badgeId = badgeId
        self.compensationType = compensationType
        self.salary = salary
        self.roleId = roleId
        self.roleName = roleName
        self.authUserId = authUserId
        self.isActive = isActive
        self.createdAt = createdAt
        self.assignedStores = assignedStores
    }
}
