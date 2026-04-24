//
//  MobilePermission.swift
//  SmartStock
//

import Foundation

enum MobilePermission: String, CaseIterable, Identifiable, Codable, Hashable {
    case addNewItem = "new_item"
    case adjustInventoryQuantity = "adjust_inventory_quantity"
    case applySaleDiscount = "apply_sale_discount"
    case changeSaleItemPrice = "change_sale_item_price"
    case changeStore = "change_store"
    case companyPreferences = "company_preferences"
    case customers = "customers"
    case departmentManagement = "department_management"
    case deviceManagement = "device_management"
    case editAccountNumber = "edit_account_number"
    case editCustomerCreditLimit = "edit_customer_credit_limit"
    case editItem = "edit_item"
    case employees = "employees"
    case makeSale = "make_sale"
    case endOfDay = "end_of_day"
    case hardwareSetup = "hardware_setup"
    case inventory = "inventory"
    case localDeviceSettings = "device_receipt_settings"
    case locationManagement = "location_management"
    case manageCustomers = "manage_customers"
    case payrollDashboard = "payroll_dashboard"
    case receiving = "receiving"
    case returns = "returns"
    case rolePermissions = "role_permissions"
    case storeTransfer = "store_transfer"
    case timeClock = "time_clock"
    case vendorManagement = "vendor_management"
    case viewCostPrice = "view_cost_price"
    case viewCreatedBy = "view_created_by"
    case viewItemDetails = "view_item_details"
    case viewReceivingHistory = "view_receiving_history"
    case viewReports = "view_reports"
    case viewSales = "view_sales"
    case viewVendor = "view_vendor"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .addNewItem:
            return "Add New Item"
        case .adjustInventoryQuantity:
            return "Adjust Inventory Quantity"
        case .applySaleDiscount:
            return "Apply Sale Discount"
        case .changeSaleItemPrice:
            return "Change Sale Item Price"
        case .changeStore:
            return "Change Store"
        case .companyPreferences:
            return "Company Preferences"
        case .customers:
            return "Customer Accounts"
        case .departmentManagement:
            return "Department Management"
        case .deviceManagement:
            return "Device Management"
        case .editAccountNumber:
            return "Edit Account Number"
        case .editCustomerCreditLimit:
            return "Set Credit Limit"
        case .editItem:
            return "Edit Item"
        case .employees:
            return "Employee Management"
        case .makeSale:
            return "Make Sale"
        case .endOfDay:
            return "End of Day"
        case .hardwareSetup:
            return "Hardware Setup"
        case .inventory:
            return "View Inventory List"
        case .localDeviceSettings:
            return "Local Device Settings"
        case .locationManagement:
            return "Location Management"
        case .manageCustomers:
            return "Manage Customers"
        case .payrollDashboard:
            return "Payroll Dashboard"
        case .receiving:
            return "Receiving Inventory"
        case .returns:
            return "Process Returns"
        case .rolePermissions:
            return "Role Management"
        case .storeTransfer:
            return "Store Transfer"
        case .timeClock:
            return "Time Clock"
        case .vendorManagement:
            return "Vendor Management"
        case .viewCostPrice:
            return "View Cost Price"
        case .viewCreatedBy:
            return "View Created By"
        case .viewItemDetails:
            return "View Item Details"
        case .viewReceivingHistory:
            return "View Receiving History"
        case .viewReports:
            return "View Reports"
        case .viewSales:
            return "View Previous Transactions"
        case .viewVendor:
            return "View Vendor"
        }
    }

    var groupTitle: String {
        switch self {
        case .makeSale, .viewSales, .returns, .endOfDay, .customers, .manageCustomers, .editCustomerCreditLimit, .editAccountNumber, .applySaleDiscount, .changeSaleItemPrice:
            return "Sales"
        case .inventory, .receiving, .storeTransfer, .editItem, .addNewItem, .adjustInventoryQuantity, .viewCostPrice, .viewItemDetails, .viewCreatedBy, .departmentManagement, .vendorManagement, .viewVendor, .viewReceivingHistory:
            return "Inventory"
        case .timeClock:
            return "Employee"
        case .employees, .rolePermissions, .companyPreferences, .locationManagement, .payrollDashboard, .viewReports:
            return "Admin"
        case .deviceManagement, .localDeviceSettings, .hardwareSetup:
            return "Device"
        case .changeStore:
            return "Operations"
        }
    }
}
