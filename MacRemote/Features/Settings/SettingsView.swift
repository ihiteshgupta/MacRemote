import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("qualityMode") private var qualityMode: String = QualityMode.auto.rawValue
    @AppStorage("defaultInputMode") private var defaultInputMode: String = InputMode.touch.rawValue
    @AppStorage("scrollSpeed") private var scrollSpeed: Double = 1.0
    @AppStorage("trackpadSensitivity") private var trackpadSensitivity: Double = 1.0
    @AppStorage("autoReconnect") private var autoReconnect = true
    @AppStorage("keepScreenAwake") private var keepScreenAwake = true
    @AppStorage("showQualityBadge") private var showQualityBadge = true

    var body: some View {
        NavigationStack {
            Form {
                displaySection
                inputSection
                connectionSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var displaySection: some View {
        Section {
            Picker("Quality", selection: $qualityMode) {
                Text("Auto").tag(QualityMode.auto.rawValue)
                Text("High").tag(QualityMode.high.rawValue)
                Text("Medium").tag(QualityMode.medium.rawValue)
                Text("Low").tag(QualityMode.low.rawValue)
            }

            Toggle("Show Quality Indicator", isOn: $showQualityBadge)
        } header: {
            Label("Display", systemImage: "display")
        } footer: {
            Text("Auto mode adjusts quality based on your network connection")
        }
    }

    private var inputSection: some View {
        Section {
            Picker("Default Mode", selection: $defaultInputMode) {
                Label("Touch", systemImage: "hand.tap.fill").tag(InputMode.touch.rawValue)
                Label("Trackpad", systemImage: "rectangle.and.hand.point.up.left.fill").tag(InputMode.trackpad.rawValue)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scroll Speed")
                    Spacer()
                    Text("\(Int(scrollSpeed * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $scrollSpeed, in: 0.25...2.0, step: 0.25)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Trackpad Sensitivity")
                    Spacer()
                    Text("\(Int(trackpadSensitivity * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $trackpadSensitivity, in: 0.5...2.0, step: 0.25)
            }
        } header: {
            Label("Input", systemImage: "hand.draw.fill")
        }
    }

    private var connectionSection: some View {
        Section {
            Toggle("Auto-Reconnect", isOn: $autoReconnect)
            Toggle("Keep Screen Awake", isOn: $keepScreenAwake)
        } header: {
            Label("Connection", systemImage: "network")
        } footer: {
            Text("Keep Screen Awake prevents your iPad from sleeping during an active session")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Protocol", value: "VNC (RFB 3.8)")
            LabeledContent("Build", value: "2025.1")
        } header: {
            Label("About", systemImage: "info.circle.fill")
        }
    }
}

#Preview {
    SettingsView()
}
