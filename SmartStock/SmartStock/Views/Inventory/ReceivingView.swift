//
//  ReceivingView.swift
//  SmartStock
//

import SwiftUI

struct ReceivingView: View {
    private enum ReceivingPage: String, CaseIterable {
        case receive = "Receive"
        case history = "History"
    }

    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedPage: ReceivingPage = .receive

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Text("Receiving")
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                if availablePages.count > 1 {
                    pageSelector
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Divider()

            Group {
                switch selectedPage {
                case .receive:
                    if canReceive {
                        ReceivingInventoryView(isEmbedded: true)
                    } else {
                        noPermissionView("You do not have permission to receive inventory.")
                    }
                case .history:
                    if canViewReceivingHistory {
                        ReceivingHistoryView(isEmbedded: true)
                    } else {
                        noPermissionView("You do not have permission to view receiving history.")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: normalizeSelectedPage)
        .onChange(of: sessionManager.currentUser?.mobilePermissions) { _, _ in
            normalizeSelectedPage()
        }
    }

    private var canReceive: Bool {
        sessionManager.currentUser?.canAccess(.receiving) == true
    }

    private var canViewReceivingHistory: Bool {
        sessionManager.currentUser?.canAccess(.viewReceivingHistory) == true
    }

    private var availablePages: [ReceivingPage] {
        ReceivingPage.allCases.filter { page in
            switch page {
            case .receive:
                return canReceive
            case .history:
                return canViewReceivingHistory
            }
        }
    }

    private var pageSelector: some View {
        GeometryReader { proxy in
            let pages = availablePages
            let selectedIndex = pages.firstIndex(of: selectedPage) ?? 0
            let segmentWidth = max((proxy.size.width - 12) / CGFloat(max(pages.count, 1)), 0)

            ZStack(alignment: .leading) {
                if !pages.isEmpty {
                    Capsule()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: segmentWidth, height: 34)
                        .offset(x: 6 + (segmentWidth * CGFloat(selectedIndex)))
                        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: selectedPage)
                }

                HStack(spacing: 0) {
                    ForEach(pages, id: \.self) { page in
                        Button {
                            selectedPage = page
                        } label: {
                            Text(page.rawValue)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selectedPage == page ? Color.primary : .secondary)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(6)
            .background(Color(.tertiarySystemBackground))
            .clipShape(Capsule())
        }
        .frame(height: 46)
    }

    private func noPermissionView(_ message: String) -> some View {
        ContentUnavailableView(
            "No Access",
            systemImage: "lock.fill",
            description: Text(message)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func normalizeSelectedPage() {
        guard !availablePages.contains(selectedPage), let firstPage = availablePages.first else {
            return
        }

        selectedPage = firstPage
    }
}
