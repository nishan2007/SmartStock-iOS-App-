//
//  LocationManagementView.swift
//  SmartStock
//

import SwiftUI

struct LocationManagementView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    var body: some View {
        CompanyPreferencesView(initialSection: .locations)
            .environmentObject(sessionManager)
    }
}
