//
//  CustomersView.swift
//  SmartStock
//

import SwiftUI

struct CustomersView: View {
    @State private var searchText = ""
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""

    var body: some View {
        List {
            Section("New Customer") {
                TextField("Full name", text: $name)
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                Button {
                    name = ""
                    phone = ""
                    email = ""
                } label: {
                    Label("Save Customer", systemImage: "person.crop.circle.badge.plus")
                }
            }

            Section("Customer List") {
                ContentUnavailableView(
                    "No Customers Loaded",
                    systemImage: "person.2",
                    description: Text("Connect this screen to your customers table to search purchase history and contact details.")
                )
            }
        }
        .navigationTitle("Customers")
        .searchable(text: $searchText, prompt: "Search customers")
    }
}
