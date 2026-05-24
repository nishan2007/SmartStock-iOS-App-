//
//  DeviceReceiptSettingsView.swift
//  SmartStock
//

import SwiftUI

struct DeviceReceiptSettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var deviceCode = ""
    @State private var savedDeviceCode = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            Section("Receipt Device Code") {
                TextField("0001", text: $deviceCode)
                    .keyboardType(.numberPad)

                LabeledContent("Saved Code", value: savedDeviceCode.isEmpty ? "—" : savedDeviceCode)
                LabeledContent("Code Preview", value: previewDeviceCode)

                if let store = sessionManager.selectedStore {
                    LabeledContent(
                        "Next Receipt Preview",
                        value: "\(store.receiptStoreCode ?? "0001")-\(previewDeviceCode)-000001"
                    )
                }

                Text("This code is stored in Devices and used in future receipt numbers for this register.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let successMessage {
                Section {
                    Text(successMessage)
                        .foregroundStyle(.green)
                }
            }

            Section {
                Button {
                    Task {
                        await save()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Device Code")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || previewDeviceCode.isEmpty || sessionManager.currentDevice == nil)
            }
        }
        .navigationTitle("Receipt Device")
        .task {
            await loadCurrentValue()
        }
    }

    private var previewDeviceCode: String {
        sanitizeCode(deviceCode)
    }

    private func loadCurrentValue() async {
        let current = sessionManager.currentDevice?.receiptDeviceCode ?? ""
        deviceCode = current
        savedDeviceCode = current
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            guard let deviceId = sessionManager.currentDevice?.id else {
                throw ReceiptNumberManagerError.missingDeviceCode
            }
            let normalized = sanitizeCode(deviceCode)
            guard !normalized.isEmpty else {
                throw ReceiptNumberManagerError.missingDeviceCode
            }

            let updatedDevice = try await DeviceService.shared.updateDeviceReceiptCode(
                deviceId: deviceId,
                receiptDeviceCode: normalized
            )
            sessionManager.handleTrackedDeviceUpdate(updatedDevice)
            deviceCode = normalized
            savedDeviceCode = normalized
            successMessage = "Device receipt code saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func sanitizeCode(_ value: String) -> String {
        let digits = value.replacingOccurrences(of: "\\D+", with: "", options: .regularExpression)
        guard let parsed = Int(digits), parsed > 0 else { return "" }
        return String(format: "%04d", min(parsed, 9999))
    }
}
