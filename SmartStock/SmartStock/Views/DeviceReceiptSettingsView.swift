//
//  DeviceReceiptSettingsView.swift
//  SmartStock
//

import SwiftUI

struct DeviceReceiptSettingsView: View {
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var deviceName = ""
    @State private var savedDeviceName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        Form {
            Section("Receipt Device Name") {
                TextField("e.g. Front Register", text: $deviceName)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled(true)

                LabeledContent("Saved Name", value: savedDeviceName.isEmpty ? "—" : savedDeviceName)
                LabeledContent("Receipt ID Preview", value: previewDeviceId)

                if let store = sessionManager.selectedStore {
                    LabeledContent(
                        "Next Receipt Preview",
                        value: "R-\(String(format: "S%03d", store.id))-\(previewDeviceId)-000001"
                    )
                }

                Text("This name is stored on the device and used in future receipt numbers for this iPhone or iPad.")
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
                        Text("Save Device Name")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving || previewDeviceId.isEmpty)
            }
        }
        .navigationTitle("Receipt Device")
        .task {
            await loadCurrentValue()
        }
    }

    private var previewDeviceId: String {
        ReceiptNumberManager.shared.previewSanitizedDeviceId(deviceName)
    }

    private func loadCurrentValue() async {
        let current = await MainActor.run {
            ReceiptNumberManager.shared.currentDeviceId()
        }
        deviceName = current
        savedDeviceName = current
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        successMessage = nil
        defer { isSaving = false }

        do {
            let updated = try await MainActor.run {
                try ReceiptNumberManager.shared.updateDeviceId(deviceName)
            }
            deviceName = updated
            savedDeviceName = updated
            successMessage = "Device receipt name saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
