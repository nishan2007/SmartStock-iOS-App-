//
//  LoadingView.swift
//  SmartStock
//
//  Created by Nishan Narain on 4/16/26.
//

//
//  LoadingView.swift
//  SmartStock
//

import SwiftUI

struct LoadingView: View {
    var text: String = "Loading..."

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(text)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
