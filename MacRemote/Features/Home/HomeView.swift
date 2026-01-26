import SwiftUI
import SwiftData

struct HomeView: View {
    @Binding var selectedConnection: SavedConnection?
    @Binding var isConnected: Bool

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedConnection.lastConnected, order: .reverse) private var savedConnections: [SavedConnection]

    @StateObject private var bonjourBrowser = BonjourBrowser()
    @State private var showAddConnection = false
    @State private var showSettings = false
    @State private var searchText = ""

    private var filteredNearbyMacs: [DiscoveredMac] {
        if searchText.isEmpty {
            return bonjourBrowser.discoveredMacs
        }
        return bonjourBrowser.discoveredMacs.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredSavedConnections: [SavedConnection] {
        if searchText.isEmpty {
            return savedConnections
        }
        return savedConnections.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.host.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Nearby Macs Section
                Section {
                    if filteredNearbyMacs.isEmpty {
                        emptyNearbyRow
                    } else {
                        ForEach(filteredNearbyMacs) { mac in
                            NearbyMacRow(mac: mac) {
                                connect(to: mac.toSavedConnection())
                            }
                        }
                    }
                } header: {
                    HStack {
                        Label("Nearby", systemImage: "wifi")
                        Spacer()
                        if bonjourBrowser.isSearching {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }

                // Saved Connections Section
                if !filteredSavedConnections.isEmpty {
                    Section {
                        ForEach(filteredSavedConnections) { connection in
                            SavedConnectionRow(connection: connection) {
                                connect(to: connection)
                            } onDelete: {
                                withAnimation {
                                    modelContext.delete(connection)
                                }
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                modelContext.delete(filteredSavedConnections[index])
                            }
                        }
                    } header: {
                        Label("Recent", systemImage: "clock")
                    }
                }

                // Add Connection Section
                Section {
                    Button {
                        showAddConnection = true
                    } label: {
                        Label("Add Connection Manually", systemImage: "plus.circle.fill")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Screen Control")
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Macs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .onAppear {
                bonjourBrowser.startBrowsing()
            }
            .onDisappear {
                bonjourBrowser.stopBrowsing()
            }
            .sheet(isPresented: $showAddConnection) {
                AddConnectionView { connection in
                    connect(to: connection)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .refreshable {
                bonjourBrowser.stopBrowsing()
                try? await Task.sleep(nanoseconds: 500_000_000)
                bonjourBrowser.startBrowsing()
            }
        }
    }

    // MARK: - Empty State

    private var emptyNearbyRow: some View {
        HStack(spacing: 12) {
            if bonjourBrowser.isSearching {
                ProgressView()
            } else {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(bonjourBrowser.isSearching ? "Searching..." : "No Macs Found")
                    .foregroundStyle(.primary)
                Text("Enable Screen Sharing on your Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func connect(to connection: SavedConnection) {
        // Save or update connection
        if !savedConnections.contains(where: { $0.host == connection.host && $0.port == connection.port }) {
            connection.lastConnected = Date()
            modelContext.insert(connection)
        } else if let existing = savedConnections.first(where: { $0.host == connection.host && $0.port == connection.port }) {
            existing.lastConnected = Date()
        }

        selectedConnection = connection
        withAnimation {
            isConnected = true
        }
    }
}

// MARK: - Row Views

struct NearbyMacRow: View {
    let mac: DiscoveredMac
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(.blue)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mac.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(mac.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SavedConnectionRow: View {
    let connection: SavedConnection
    let onConnect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: connection.isManual ? "globe" : "desktopcomputer")
                    .font(.title2)
                    .foregroundStyle(connection.isManual ? .orange : .gray)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    HStack(spacing: 4) {
                        Text(connection.connectionString)
                        if let lastConnected = connection.lastConnected {
                            Text("•")
                            Text(lastConnected, style: .relative)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

#Preview {
    HomeView(selectedConnection: .constant(nil), isConnected: .constant(false))
        .modelContainer(for: SavedConnection.self, inMemory: true)
}
