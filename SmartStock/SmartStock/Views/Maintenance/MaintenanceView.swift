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

    private enum TicketFilter: String, CaseIterable, Identifiable {
        case active = "Active"
        case open = "Open"
        case inProgress = "In Progress"
        case waitingParts = "Waiting Parts"
        case resolved = "Resolved"
        case all = "All"

        var id: String { rawValue }
    }

    @EnvironmentObject private var sessionManager: SessionManager
    @State private var selectedTab: MaintenanceTab = .machines
    @State private var machines: [MaintenanceMachine] = []
    @State private var parts: [MaintenancePart] = []
    @State private var logs: [MaintenanceLog] = []
    @State private var tickets: [MaintenanceTicket] = []
    @State private var ticketSearchText = ""
    @State private var ticketFilter: TicketFilter = .active
    @State private var ticketPendingResolve: MaintenanceTicket?
    @State private var selectedTicket: MaintenanceTicket?
    @State private var swipeResolutionSummary = ""
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
        .searchable(
            text: $ticketSearchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: "Search tickets"
        )
        .toolbar {
            if selectedTab == .tickets && canViewMaintenance {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        TicketHistoryView()
                            .environmentObject(sessionManager)
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
        }
        .sheet(item: $ticketPendingResolve) { ticket in
            NavigationStack {
                resolveTicketSheet(ticket)
            }
        }
        .navigationDestination(item: $selectedTicket) { ticket in
            TicketDetailsView(initialTicket: ticket) {
                await loadData()
            }
            .environmentObject(sessionManager)
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
            Section {
                Picker("Filter", selection: $ticketFilter) {
                    ForEach(TicketFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Tickets") {
                if filteredTickets.isEmpty {
                    ContentUnavailableView("No Tickets", systemImage: "ticket")
                } else {
                    ForEach(filteredTickets) { ticket in
                        Button {
                            selectedTicket = ticket
                        } label: {
                            TicketSummaryRow(ticket: ticket)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !ticket.isResolvedOrClosed {
                                Button {
                                    ticketPendingResolve = ticket
                                    swipeResolutionSummary = ticket.resolutionSummary ?? ""
                                } label: {
                                    Label("Resolve", systemImage: "checkmark.circle.fill")
                                }
                                .tint(.green)
                            }
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

    private var canViewMaintenance: Bool {
        sessionManager.currentUser?.canAccess(.maintenanceManagement) == true
    }

    private var filteredTickets: [MaintenanceTicket] {
        tickets
            .filter(matchesTicketFilter)
            .filter(matchesTicketSearch)
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

    private func resolveTicket(_ ticket: MaintenanceTicket, resolutionSummary: String) async {
        do {
            try await MaintenanceService.shared.updateTicketStatus(
                ticketId: ticket.id,
                status: .resolved,
                resolutionSummary: resolutionSummary
            )
            ticketPendingResolve = nil
            swipeResolutionSummary = ""
            await loadData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveTicketSheet(_ ticket: MaintenanceTicket) -> some View {
        Form {
            Section("Resolution Summary") {
                Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                    .font(.headline)

                TextField("What fixed the issue?", text: $swipeResolutionSummary, axis: .vertical)
                    .lineLimit(4...8)
            }
        }
        .navigationTitle("Resolve Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    ticketPendingResolve = nil
                    swipeResolutionSummary = ""
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Resolve") {
                    Task { await resolveTicket(ticket, resolutionSummary: swipeResolutionSummary) }
                }
                .disabled(swipeResolutionSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func matchesTicketFilter(_ ticket: MaintenanceTicket) -> Bool {
        switch ticketFilter {
        case .active:
            return !ticket.isResolvedOrClosed
        case .open:
            return ticket.status == MaintenanceTicketStatus.open.rawValue
        case .inProgress:
            return ticket.status == MaintenanceTicketStatus.inProgress.rawValue
        case .waitingParts:
            return ticket.status == MaintenanceTicketStatus.waitingParts.rawValue
        case .resolved:
            return ticket.status == MaintenanceTicketStatus.resolved.rawValue
        case .all:
            return true
        }
    }

    private func matchesTicketSearch(_ ticket: MaintenanceTicket) -> Bool {
        let searchText = ticketSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchText.isEmpty else { return true }

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

        return haystack.localizedCaseInsensitiveContains(searchText)
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

struct TicketSummaryRow: View {
    let ticket: MaintenanceTicket

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ticket.problemSummary?.nilIfBlank ?? "Ticket #\(ticket.id)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(ticket.displayOpenedAt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Created by: \(ticket.displayOpenedBy)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 5) {
                    TicketBadge(
                        title: ticket.displayPriority,
                        color: priorityColor,
                        systemImage: "exclamationmark.circle"
                    )

                    TicketBadge(
                        title: ticket.displayStatus,
                        color: statusColor,
                        systemImage: "circle.fill"
                    )
                }
            }

            HStack {
                metricView(title: "Machine", value: ticket.machineId.map { "#\($0)" } ?? "None")
                Spacer()
                metricView(title: "Assigned", value: ticket.assignedToName?.nilIfBlank ?? "Open")
                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                if let dueDate = ticket.dueDate?.nilIfBlank {
                    Text("Due: \(dueDate)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let resolutionSummary = ticket.resolutionSummary?.nilIfBlank {
                    Text("Resolution: \(resolutionSummary)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if let notes = ticket.notes?.nilIfBlank {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor.opacity(0.45), lineWidth: 1)
        )
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private var statusColor: Color {
        switch ticket.status {
        case MaintenanceTicketStatus.open.rawValue:
            return .orange
        case MaintenanceTicketStatus.inProgress.rawValue:
            return .blue
        case MaintenanceTicketStatus.waitingParts.rawValue:
            return .purple
        case MaintenanceTicketStatus.resolved.rawValue, MaintenanceTicketStatus.closed.rawValue:
            return .green
        case MaintenanceTicketStatus.canceled.rawValue:
            return .secondary
        default:
            return .secondary
        }
    }

    private var priorityColor: Color {
        switch ticket.priority {
        case MaintenanceTicketPriority.low.rawValue:
            return .secondary
        case MaintenanceTicketPriority.normal.rawValue:
            return .blue
        case MaintenanceTicketPriority.high.rawValue:
            return .orange
        case MaintenanceTicketPriority.urgent.rawValue:
            return .red
        default:
            return .secondary
        }
    }

    private var rowBackground: Color {
        switch ticket.priority {
        case MaintenanceTicketPriority.low.rawValue:
            return Color(.secondarySystemBackground)
        case MaintenanceTicketPriority.normal.rawValue:
            return Color.blue.opacity(0.08)
        case MaintenanceTicketPriority.high.rawValue:
            return Color.orange.opacity(0.14)
        case MaintenanceTicketPriority.urgent.rawValue:
            return Color.red.opacity(0.11)
        default:
            return Color(.secondarySystemBackground)
        }
    }

    private var borderColor: Color {
        switch ticket.priority {
        case MaintenanceTicketPriority.low.rawValue:
            return .gray
        default:
            return priorityColor
        }
    }
}

private struct TicketBadge: View {
    let title: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.75), lineWidth: 1)
            }
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
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
