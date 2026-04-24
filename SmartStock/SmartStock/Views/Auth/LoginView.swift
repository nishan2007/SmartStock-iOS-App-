//
//  LoginView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/15/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var sessionManager: SessionManager

    @State private var username = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Text("SmartStock")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Employee Login")
                    .foregroundColor(.secondary)

                VStack(spacing: 14) {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)

                    SecureField("Password", text: $password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }

                if let error = sessionManager.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                        .padding(.horizontal)
                }

                Button {
                    Task {
                        _ = await sessionManager.signIn(username: username, password: password)
                    }
                } label: {
                    if sessionManager.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Log In")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .disabled(sessionManager.isLoading || username.isEmpty || password.isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Login")
        }
    }
}
