//
//  LoadingView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

import SwiftUI

struct LoadingView: View {
    var text: String = "Loading..."
    var showsBranding = false

    var body: some View {
        VStack(spacing: showsBranding ? 24 : 12) {
            if showsBranding {
                VStack(spacing: 18) {
                    Image("AppLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 18, y: 10)

                    Image("CompanyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 190, maxHeight: 72)
                        .accessibilityLabel("Company logo")
                }
            }

            ProgressView()

            Text(text)
                .foregroundColor(.secondary)
                .font(.subheadline.weight(.medium))
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(.systemBackground),
                    Color.blue.opacity(showsBranding ? 0.08 : 0),
                    Color(.systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}
