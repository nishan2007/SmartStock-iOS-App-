//
//  MaintenanceView.swift
//  SmartStock
//

import SwiftUI

struct MaintenanceView: View {
    private enum MaintenanceTab: String, CaseIterable, Identifiable {
        case machines = "Machines"
        case parts = "Parts"
        case logs = "Logs"
        case tickets = "Tickets"

        var id: String { rawValue }
    }

    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedTab: MaintenanceTab = .machines
    @State private var machines: [MaintenanceMachine] = []
    @State private var parts: [MaintenancePart] = []
    @State private var logs: [MaintenanceLog] = []
    @State private var tickets: [MaintenanceTicket] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !canViewMaintenance {
                Section {
                    ContentUnavailableView(
                        "Maintenance Locked",
                        systemImage: "lock.shield",
                        description: Text("Your role does not have Maintenance access.")
                    )
                }
            } else {
                Section {
                    Picker("Maintenance Section", selection: $selectedTab) {
                        ForEach(MaintenanceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }

                if isLoading {
                    Section { ProgressView("Loading maintenance...") }
                } else {
                    selectedSection
                }
            }
        }
        .navigationTitle("Maintenance")
        .task {
            guard canViewMaintenance else { return }
            await loadData()
        }
        .refreshable {
            guard canViewMaintenance else { return }
            await loadData()
        }
    }

    @ViewBuilder
    private var selectedSection: some View {
        switch selectedTab {
        case .machines:
            Section("Machines") {
                if machines.isEmpty {
                    ContentUnavailableView("No Machines", systemImage: "wrench.and.screwdriver")
                } else {
                    ForEach(machines) { machine in
                        NavigationLink {
                            MachineDetailsView(machine: machine)
                                .environmentObject(sessionManager)
                        } label: {
                            MachineSummaryRow(machine: machine)
                        }
                    }
                }
            }
        case .parts:
            Section("Parts") {
                if parts.isEmpty {
                    ContentUnavailableView("No Parts", systemImage: "gearshape.2")
                } else {
                    ForEach(parts) { part in
                        PartSummaryRow(part: part)
                    }
                }
            }
        case .logs:
            Section("Maintenance Logs") {
                if logs.isEmpty {
                    ContentUnavailableView("No Logs", systemImage: "doc.text.magnifyingglass")
                } else {
                    ForEach(logs) { log in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(log.summary?.nilIfBlank ?? log.displayServiceType)
                                .font(.headline)

                            Text(log.serviceDate?.nilIfBlank ?? log.createdAt?.nilIfBlank ?? "No date")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text(log.displayServiceType)
                                if let technicianName = log.technicianName?.nilIfBlank {
                                    Text("Tech: \(technicianName)")
                                }
                                if log.laborHours > 0 {
                                    Text("Hours: \(log.laborHours.maintenanceNumberText)")
                                }
                                if log.totalCost > 0 {
                                    Text("Cost: \(log.totalCost.maintenanceCurrencyText)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let details = log.details?.nilIfBlank {
                                Text(details)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let partsUsed = log.partsUsed?.nilIfBlank {
                                Text("Parts: \(partsUsed)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        case .tickets:
            Section("Tickets") {
                if tickets.isEmpty {
                    ContentUnavailableView("No Tickets", systemImage: "ticket")
                } else {
                    ForEach(tickets) { ticket in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                                    .font(.headline)
                                Spacer()
                                Text(ticket.displayStatus)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }

                            Text(ticket.openedAt?.nilIfBlank ?? "No open date")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Text("Priority: \(ticket.displayPriority)")
                                if let assignedToName = ticket.assignedToName?.nilIfBlank {
                                    Text("Assigned: \(assignedToName)")
                                }
                                if let dueDate = ticket.dueDate?.nilIfBlank {
                                    Text("Due: \(dueDate)")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let resolutionSummary = ticket.resolutionSummary?.nilIfBlank {
                                Text("Resolution: \(resolutionSummary)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let notes = ticket.notes?.nilIfBlank {
                                Text(notes)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private var canViewMaintenance: Bool {
        sessionManager.currentUser?.canAccess(.maintenanceManagement) == true
    }

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            async let machinesTask = MaintenanceService.shared.fetchMachines()
            async let partsTask = MaintenanceService.shared.fetchParts()
            async let logsTask = MaintenanceService.shared.fetchLogs()
            async let ticketsTask = MaintenanceService.shared.fetchTickets()

            machines = try await machinesTask
            parts = try await partsTask
            logs = try await logsTask
            tickets = try await ticketsTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct MachineSummaryRow: View {
    let machine: MaintenanceMachine

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(machine.machineName)
                    .font(.headline)
                Spacer()
                Text(machine.status.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            if !machine.subtitle.isEmpty {
                Text(machine.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let serialNumber = machine.serialNumber?.nilIfBlank {
                Text("Serial: \(serialNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch machine.status {
        case .active:
            return .green
        case .needsService:
            return .orange
        case .down:
            return .red
        case .retired:
            return .secondary
        }
    }
}

struct PartSummaryRow: View {
    let part: MaintenancePart

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(part.partName)
                    .font(.headline)
                Spacer()
                Text(part.isActive ? "Active" : "Inactive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(part.isActive ? .green : .secondary)
            }

            if !part.detailText.isEmpty {
                Text(part.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("On hand: \(part.quantityOnHand.maintenanceNumberText) • Reorder at: \(part.reorderPoint.maintenanceNumberText) • Buy: \(part.reorderQuantity.maintenanceNumberText)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Decimal {
    var maintenanceCurrencyText: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "$\(maintenanceNumberText)"
    }
}
