//
//  CashDrawerManagementView.swift
//  SmartStock
//

import SwiftUI

struct CashDrawerManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        CompanyPreferencesView(initialSection: .cashDrawers)
            .environmentObject(sessionManager)
    }
}
