//
//  AddEmployeeView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  AddEmployeeView.swift
//  SmartStock
//

import SwiftUI

struct AddEmployeeView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = EmployeeFormViewModel()

    var onSaved: (() async -> Void)?

    var body: some View {
        Form {
            if let error = viewModel.errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                }
            }

            EmployeeFormFields(viewModel: viewModel, showPasswordField: true)
        }
        .navigationTitle("Add Employee")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task {
                            let didSave = await viewModel.save()
                            if didSave {
                                if let onSaved {
                                    await onSaved()
                                }
                                dismiss()
                            }
                        }
                    }
                }
            }
        }
        .task {
            await viewModel.loadDependencies()
        }
        .overlay {
            if viewModel.isLoading {
                LoadingView()
                    .background(Color(.systemBackground).opacity(0.85))
            }
        }
    }
}
