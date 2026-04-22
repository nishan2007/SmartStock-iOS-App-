//
//  MobilePermission.swift
//  SmartStock
//

import Foundation

enum MobilePermission: String, CaseIterable, Identifiable, Codable, Hashable {
    case makeSale = "make_sale"
    case viewSales = "view_sales"
    case returns = "returns"
    case endOfDay = "end_of_day"
    case customers = "customers"
    case inventory = "inventory"
    case receiving = "receiving"
    case storeTransfer = "store_transfer"
    case editItem = "edit_item"
    case newItem = "new_item"
    case timeClock = "time_clock"
    case employees = "employees"
    case rolePermissions = "role_permissions"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .makeSale:
            return "Make Sale"
        case .viewSales:
            return "View Sales"
        case .returns:
            return "Returns"
        case .endOfDay:
            return "End of Day"
        case .customers:
            return "Customers"
        case .inventory:
            return "Inventory"
        case .receiving:
            return "Receiving"
        case .storeTransfer:
            return "Store Transfer"
        case .editItem:
            return "Edit Item"
        case .newItem:
            return "New Item"
        case .timeClock:
            return "Time Clock"
        case .employees:
            return "Employees"
        case .rolePermissions:
            return "Role Permissions"
        }
    }

    var groupTitle: String {
        switch self {
        case .makeSale, .viewSales, .returns, .endOfDay, .customers:
            return "Sales"
        case .inventory, .receiving, .storeTransfer, .editItem, .newItem:
            return "Inventory"
        case .timeClock:
            return "Employee"
        case .employees, .rolePermissions:
            return "Admin"
        }
    }
}
