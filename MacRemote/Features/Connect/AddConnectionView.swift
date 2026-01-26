import SwiftUI

struct AddConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var port = "5900"
    @FocusState private var focusedField: Field?

    enum Field {
        case name, host, port
    }

    var onConnect: (SavedConnection) -> Void

    private var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Office Mac"))
                        .focused($focusedField, equals: .name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Display Name")
                } footer: {
                    Text("Optional friendly name for this connection")
                }

                Section {
                    TextField("Host", text: $host, prompt: Text("192.168.1.100"))
                        .focused($focusedField, equals: .host)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Port", text: $port, prompt: Text("5900"))
                        .focused($focusedField, equals: .port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Connection Details")
                } footer: {
                    Text("Enter the IP address or hostname of the Mac you want to connect to. The default VNC port is 5900.")
                }
            }
            .navigationTitle("New Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        let connection = SavedConnection(
                            name: name.trimmingCharacters(in: .whitespaces),
                            host: host.trimmingCharacters(in: .whitespaces),
                            port: Int(port) ?? 5900,
                            isManual: true
                        )
                        onConnect(connection)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                focusedField = .host
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    AddConnectionView { _ in }
}
