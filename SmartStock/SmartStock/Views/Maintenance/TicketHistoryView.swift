//
//  TicketHistoryView.swift
//  SmartStock
//

import SwiftUI

struct TicketHistoryView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @State private var tickets: [MaintenanceTicket] = []
    @State private var selectedTicket: MaintenanceTicket?
    @State private var searchText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !canViewMaintenance {
                Section {
                    ContentUnavailableView(
                        "Ticket History Locked",
                        systemImage: "lock.shield",
                        description: Text("Your role does not have Maintenance access.")
                    )
                }
            } else {
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                Section("Resolved Tickets") {
                    if isLoading {
                        ProgressView("Loading history...")
                    } else if filteredTickets.isEmpty {
                        ContentUnavailableView("No Ticket History", systemImage: "clock.arrow.circlepath")
                    } else {
                        ForEach(filteredTickets) { ticket in
                            Button {
                                selectedTicket = ticket
                            } label: {
                                TicketSummaryRow(ticket: ticket)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4))
                        }
                    }
                }
            }
        }
        .navigationTitle("Ticket History")
        .searchable(text: $searchText, prompt: "Search history")
        .task {
            guard canViewMaintenance else { return }
            await loadHistory()
        }
        .refreshable {
            guard canViewMaintenance else { return }
            await loadHistory()
        }
        .navigationDestination(item: $selectedTicket) { ticket in
            TicketDetailsView(initialTicket: ticket) {
                await loadHistory()
            }
            .environmentObject(sessionManager)
        }
    }

    private var canViewMaintenance: Bool {
        sessionManager.currentUser?.canAccess(.maintenanceManagement) == true
    }

    private var filteredTickets: [MaintenanceTicket] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return tickets }

        return tickets.filter { ticket in
            let haystack = [
                ticket.problemSummary,
                ticket.notes,
                ticket.resolutionSummary,
                ticket.assignedToName,
                ticket.openedByUserName,
                ticket.priority,
                ticket.status,
                ticket.machineId.map { "machine \($0)" },
                "ticket \(ticket.id)"
            ]
            .compactMap { $0 }
            .joined(separator: " ")

            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    private func loadHistory() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            tickets = try await MaintenanceService.shared.fetchTicketHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
