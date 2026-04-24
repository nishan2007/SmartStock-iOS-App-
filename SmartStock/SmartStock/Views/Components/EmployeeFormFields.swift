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
            TextField("Full Name", text: $viewModel.fullName)
                .textInputAutocapitalization(.words)

            TextField("Username", text: $viewModel.username)
                .autocorrectionDisabled()

            TextField("Email", text: $viewModel.email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Phone", text: $viewModel.phone)
                .keyboardType(.phonePad)
        }

        if showPasswordField {
            Section(viewModel.isEditing ? "Change Password (Optional)" : "Password") {
                SecureField(
                    viewModel.isEditing ? "Leave blank to keep current password" : "Password",
                    text: $viewModel.password
                )
            }
        }

        Section("Role") {
            Picker("Role", selection: Binding(
                get: { viewModel.selectedRoleId ?? 0 },
                set: { viewModel.selectedRoleId = $0 }
            )) {
                ForEach(viewModel.roles) { role in
                    Text(role.name).tag(role.id)
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
}
