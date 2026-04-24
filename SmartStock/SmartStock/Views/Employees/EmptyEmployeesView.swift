//
//  EmptyEmployeesView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  EmptyEmployeesView.swift
//  SmartStock
//

import SwiftUI

struct EmptyEmployeesView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.sequence")
                .font(.system(size: 42))

            Text("No employees found")
                .font(.headline)

            Text("Add an employee to get started.")
                .foregroundColor(.secondary)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}
