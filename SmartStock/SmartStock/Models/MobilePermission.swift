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
    case cashDrawerManagement = "cash_drawer_management"
    case companyPreferences = "company_preferences"
    case createCustomOrder = "create_custom_order"
    case customOrderCancel = "custom_order_cancel"
    case customOrderDepositOverride = "custom_order_deposit_override"
    case customOrderDepositSettings = "custom_order_deposit_settings"
    case customOrderLineDelivery = "custom_order_line_delivery"
    case customOrderLineDiscount = "custom_order_line_discount"
    case customOrderLineReturns = "custom_order_line_returns"
    case customOrderOverrides = "custom_order_overrides"
    case customOrderProductionSteps = "custom_order_production_steps"
    case customOrderRefundApproval = "custom_order_refund_approval"
    case customOrderRefundApprovalSettings = "custom_order_refund_approval_settings"
    case customOrderRefunds = "custom_order_refunds"
    case customOrderItems = "custom_order_items"
    case customOrderPrintMaterials = "custom_order_print_materials"
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
    case machineManagement = "machine_management"
    case maintenanceManagement = "maintenance_management"
    case manageCustomers = "manage_customers"
    case manageCustomOrders = "manage_custom_orders"
    case ordersEndOfDay = "orders_end_of_day"
    case ordersManagerDashboard = "orders_manager_dashboard"
    case payrollDashboard = "payroll_dashboard"
    case partsManagement = "parts_management"
    case receiving = "receiving"
    case returns = "returns"
    case rolePermissions = "role_permissions"
    case storeTransfer = "store_transfer"
    case timeClock = "time_clock"
    case vendorManagement = "vendor_management"
    case viewCostPrice = "view_cost_price"
    case viewAssignedCustomOrders = "view_assigned_custom_orders"
    case viewAllStoresInventory = "view_all_stores_inventory"
    case viewCreatedBy = "view_created_by"
    case viewItemDetails = "view_item_details"
    case viewReceivingHistory = "view_receiving_history"
    case viewReports = "view_reports"
    case viewSaleAudit = "view_sale_audit"
    case viewSales = "view_sales"
    case viewVendor = "view_vendor"
    case verifyStoreTransferQuantity = "verify_store_transfer_quantity"
    case exportSaleAudit = "export_sale_audit"

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
        case .cashDrawerManagement:
            return "Cash Drawer Management"
        case .companyPreferences:
            return "Company Preferences"
        case .createCustomOrder:
            return "Create Custom Order"
        case .customOrderCancel:
            return "Cancel Custom Orders"
        case .customOrderDepositOverride:
            return "Override Custom Order Deposit"
        case .customOrderDepositSettings:
            return "Custom Order Deposit Settings"
        case .customOrderLineDelivery:
            return "Deliver Custom Order Lines"
        case .customOrderLineDiscount:
            return "Discount Custom Order Lines"
        case .customOrderLineReturns:
            return "Return Custom Order Lines"
        case .customOrderOverrides:
            return "Custom Order Overrides"
        case .customOrderProductionSteps:
            return "Custom Order Production Steps"
        case .customOrderRefundApproval:
            return "Approve Custom Order Refunds"
        case .customOrderRefundApprovalSettings:
            return "Custom Order Refund Approval Settings"
        case .customOrderRefunds:
            return "Custom Order Refunds"
        case .customOrderItems:
            return "Custom Order Items"
        case .customOrderPrintMaterials:
            return "Custom Order Print Materials"
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
        case .machineManagement:
            return "Machine Management"
        case .maintenanceManagement:
            return "Maintenance Management"
        case .manageCustomers:
            return "Manage Customers"
        case .manageCustomOrders:
            return "Manage Custom Orders"
        case .ordersEndOfDay:
            return "Orders End Of Day"
        case .ordersManagerDashboard:
            return "Orders Manager Dashboard"
        case .payrollDashboard:
            return "Payroll Dashboard"
        case .partsManagement:
            return "Parts Management"
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
        case .viewAssignedCustomOrders:
            return "View Assigned Custom Orders"
        case .viewAllStoresInventory:
            return "View All Stores Inventory"
        case .viewCreatedBy:
            return "View Created By"
        case .viewItemDetails:
            return "View Item Details"
        case .viewReceivingHistory:
            return "View Receiving History"
        case .viewReports:
            return "View Reports"
        case .viewSaleAudit:
            return "View Sale Audit"
        case .viewSales:
            return "View Previous Transactions"
        case .viewVendor:
            return "View Vendor"
        case .verifyStoreTransferQuantity:
            return "Verify Store Transfer Quantity"
        case .exportSaleAudit:
            return "Export Sale Audit"
        }
    }

    var groupTitle: String {
        switch self {
        case .makeSale, .viewSales, .returns, .endOfDay, .customers, .manageCustomers, .editCustomerCreditLimit, .editAccountNumber, .applySaleDiscount, .changeSaleItemPrice, .viewSaleAudit, .exportSaleAudit, .createCustomOrder, .manageCustomOrders, .viewAssignedCustomOrders, .ordersManagerDashboard, .ordersEndOfDay, .customOrderRefunds, .customOrderLineReturns, .customOrderLineDelivery, .customOrderLineDiscount, .customOrderDepositOverride, .customOrderRefundApproval, .customOrderProductionSteps, .customOrderCancel, .customOrderOverrides, .cashDrawerManagement:
            return "Sales"
        case .inventory, .receiving, .storeTransfer, .verifyStoreTransferQuantity, .editItem, .addNewItem, .adjustInventoryQuantity, .viewCostPrice, .viewAllStoresInventory, .viewItemDetails, .viewCreatedBy, .departmentManagement, .vendorManagement, .viewVendor, .viewReceivingHistory, .maintenanceManagement, .machineManagement, .partsManagement, .customOrderItems, .customOrderPrintMaterials:
            return "Inventory"
        case .timeClock:
            return "Employee"
        case .employees, .rolePermissions, .companyPreferences, .locationManagement, .payrollDashboard, .viewReports, .customOrderDepositSettings, .customOrderRefundApprovalSettings:
            return "Admin"
        case .deviceManagement, .localDeviceSettings, .hardwareSetup:
            return "Device"
        case .changeStore:
            return "Operations"
        }
    }
}
