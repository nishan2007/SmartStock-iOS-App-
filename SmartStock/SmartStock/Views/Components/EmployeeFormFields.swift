//
//  EmployeeFormFields.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmployeeFormFields.swift
//  SmartStock
//

import SwiftUI

struct EmployeeFormFields: View {
    @ObservedObject var viewModel: EmployeeFormViewModel
    let showPasswordField: Bool

    var body: some View {
        Section("Basic Info") {
            requiredField(.firstName, isEmpty: isBlank(viewModel.firstName)) {
                TextField("First Name", text: $viewModel.firstName)
                    .textInputAutocapitalization(.words)
            }

            TextField("Middle Name (optional)", text: $viewModel.middleName)
                .textInputAutocapitalization(.words)

            requiredField(.lastName, isEmpty: isBlank(viewModel.lastName)) {
                TextField("Last Name", text: $viewModel.lastName)
                    .textInputAutocapitalization(.words)
            }

            TextField("Username (auto-generated)", text: $viewModel.username)
                .autocorrectionDisabled()

            requiredField(.email, isEmpty: isBlank(viewModel.email)) {
                TextField("Email", text: $viewModel.email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            requiredField(.phone, isEmpty: isBlank(viewModel.phone)) {
                TextField("Phone", text: $viewModel.phone)
                    .keyboardType(.phonePad)
            }

            TextField("Badge ID (auto-generated)", text: $viewModel.badgeId)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
        }

        Section("Compensation") {
            requiredField(.compensationType, isEmpty: isBlank(viewModel.compensationType)) {
                TextField("Compensation Type", text: $viewModel.compensationType)
                    .textInputAutocapitalization(.words)
            }

            requiredField(.salary, isEmpty: isBlank(viewModel.salaryText)) {
                TextField("Salary", text: $viewModel.salaryText)
                    .keyboardType(.decimalPad)
            }
        }

        if showPasswordField {
            Section(viewModel.isEditing ? "Change Password (Optional)" : "Password") {
                requiredField(.password, isEmpty: isBlank(viewModel.password)) {
                    SecureField(
                        viewModel.isEditing ? "Leave blank to keep current password" : "Password",
                        text: $viewModel.password
                    )
                }
            }
        }

        Section("Role") {
            requiredField(.role, isEmpty: viewModel.selectedRoleId == nil) {
                Picker("Role", selection: Binding(
                    get: { viewModel.selectedRoleId ?? 0 },
                    set: { viewModel.selectedRoleId = $0 }
                )) {
                    ForEach(viewModel.roles) { role in
                        Text(role.name).tag(role.id)
                    }
                }
            }
        }

        Section("Status") {
            Toggle("Active", isOn: $viewModel.isActive)
        }

        Section("Store Access") {
            if viewModel.stores.isEmpty {
                Text("No stores found.")
                    .foregroundColor(.secondary)
            } else {
                ForEach(viewModel.stores, id: \.id) { store in
                    Button {
                        if viewModel.selectedStoreIds.contains(store.id) {
                            viewModel.selectedStoreIds.remove(store.id)
                        } else {
                            viewModel.selectedStoreIds.insert(store.id)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(store.name)
                                    .foregroundColor(.primary)

                                if let address = store.address, !address.isEmpty {
                                    Text(address)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            Image(systemName: viewModel.selectedStoreIds.contains(store.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(viewModel.selectedStoreIds.contains(store.id) ? .blue : .secondary)
                        }
                    }
                }
            }
        }
    }

    private func isMissing(_ field: EmployeeFormRequiredField, isEmpty: Bool) -> Bool {
        viewModel.missingRequiredFields.contains(field) && isEmpty
    }

    private func isBlank(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func requiredField<Content: View>(
        _ field: EmployeeFormRequiredField,
        isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let missing = isMissing(field, isEmpty: isEmpty)

        content()
            .padding(missing ? 8 : 0)
            .background {
                if missing {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                }
            }
            .overlay {
                if missing {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.red, lineWidth: 1)
                }
            }
    }
}
