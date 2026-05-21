//
//  CustomOrderPreferencesView.swift
//  SmartStock
//

import SwiftUI

struct CustomOrderPreferencesView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    private let service = CustomOrderService()

    @State private var minimumDepositPercent = "0"
    @State private var refundApprovalLimit = "0"
    @State private var isSaving = false
    @State private var message: String?

    var body: some View {
        Form {
            if let message {
                Section { Text(message).foregroundStyle(message.hasPrefix("Saved") ? .green : .red) }
            }

            Section("Custom Orders") {
                LabeledContent("Minimum deposit %") {
                    TextField("0.00", text: $minimumDepositPercent)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(!canEditDeposit)
                }

                LabeledContent("Refund approval limit") {
                    TextField("0.00", text: $refundApprovalLimit)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .disabled(!canEditRefundApproval)
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    Label(isSaving ? "Saving" : "Save Preferences", systemImage: "checkmark.circle")
                }
                .disabled(isSaving || (!canEditDeposit && !canEditRefundApproval))
            }
        }
        .navigationTitle("Company Preferences")
        .task { await load() }
    }

    private var canEditDeposit: Bool {
        sessionManager.currentUser?.canAccess(.customOrderDepositSettings) == true
            || sessionManager.currentUser?.canAccess(.companyPreferences) == true
    }

    private var canEditRefundApproval: Bool {
        sessionManager.currentUser?.canAccess(.customOrderRefundApprovalSettings) == true
            || sessionManager.currentUser?.canAccess(.companyPreferences) == true
    }

    private func load() async {
        do {
            let prefs = try await service.fetchCompanyPreferences(locationId: sessionManager.selectedStore?.id)
            minimumDepositPercent = String(format: "%.2f", prefs.customOrderMinimumDepositPercent)
            refundApprovalLimit = String(format: "%.2f", prefs.customOrderRefundApprovalLimit)
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        do {
            try await service.saveCompanyPreferences(
                CustomOrderCompanyPreferences(
                    customOrderMinimumDepositPercent: Double(minimumDepositPercent) ?? 0,
                    customOrderRefundApprovalLimit: Double(refundApprovalLimit) ?? 0
                ),
                locationId: sessionManager.selectedStore?.id
            )
            message = "Saved custom order preferences."
        } catch {
            message = error.localizedDescription
        }
    }
}
