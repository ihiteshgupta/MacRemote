import SwiftUI

struct SessionView: View {
    let connection: SavedConnection
    @Binding var isConnected: Bool

    @StateObject private var vncClient = VNCClient()
    @State private var inputMode: InputMode = .touch
    @State private var displayMode: DisplayMode = .all  // Show full screen by default
    @State private var showAuthPrompt = false
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var showToolbar = true
    @State private var toolbarOpacity: Double = 1.0
    @State private var spinnerRotation: Double = 0
    @State private var connectionTimeoutTask: Task<Void, Never>?
    @State private var isKeyboardActive = false

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()

                    screenContent(in: geometry)

                    // Floating toolbar
                    VStack {
                        Spacer()
                        if showToolbar {
                            floatingToolbar
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3), value: showToolbar)

                    // Connection status overlay
                    if vncClient.state == .connected {
                        statusBadge
                    }
                }
                .onTapGesture(count: 3) {
                    withAnimation {
                        showToolbar.toggle()
                    }
                }
            }

            // Keyboard input handler - uses UIKit for reliable hardware keyboard support
            // Needs proper size for keyboard to appear, but positioned to not interfere
            VStack {
                Spacer()
                KeyboardInputView(
                    onKeyEvent: { event in
                        vncClient.sendKeyEvent(event)
                    },
                    isActive: $isKeyboardActive
                )
                .frame(height: 44)
                .opacity(isKeyboardActive ? 0.01 : 0)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .ignoresSafeArea()
        .onAppear {
            vncClient.connect(host: connection.host, port: connection.port)

            // Connection timeout after 20 seconds
            connectionTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                switch vncClient.state {
                case .connecting:
                    errorMessage = "Connection timed out (connecting). Cannot reach \(connection.host):\(connection.port)"
                case .handshaking:
                    errorMessage = "Connection timed out (handshaking). VNC handshake failed - the Mac may not have VNC password enabled.\n\nEnable it in: System Settings → Sharing → Screen Sharing → (i) → 'VNC viewers may control screen with password'"
                case .authenticating:
                    errorMessage = "Connection timed out (authenticating). Authentication is taking too long."
                default:
                    break
                }
            }

            // Auto-hide toolbar after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                withAnimation {
                    toolbarOpacity = 0.6
                }
            }
        }
        .onDisappear {
            connectionTimeoutTask?.cancel()
            vncClient.disconnect()
        }
        .onChange(of: vncClient.state) { _, newState in
            handleStateChange(newState)
        }
        .sheet(isPresented: $showAuthPrompt) {
            PasswordPromptView(
                serverName: connection.displayName,
                onSubmit: { enteredPassword in
                    password = enteredPassword
                    vncClient.authenticate(password: enteredPassword)
                    showAuthPrompt = false
                },
                onCancel: {
                    showAuthPrompt = false
                    disconnect()
                }
            )
        }
        .alert("Connection Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil; disconnect() } }
        )) {
            Button("OK") {
                disconnect()
            }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var stateDescription: String {
        switch vncClient.state {
        case .connecting: return "Connecting..."
        case .handshaking: return "Handshaking..."
        case .authenticating: return "Authenticating..."
        default: return "Connecting..."
        }
    }

    // MARK: - Screen Content

    @ViewBuilder
    private func screenContent(in geometry: GeometryProxy) -> some View {
        switch vncClient.state {
        case .disconnected:
            disconnectedView

        case .connecting, .handshaking:
            connectingView

        case .authenticating:
            authenticatingView

        case .connected:
            ScreenCanvasView(
                frameBuffer: vncClient.frameBuffer,
                inputMode: inputMode,
                displayMode: displayMode,
                onMouseEvent: { vncClient.sendMouseEvent($0) },
                onKeyEvent: { vncClient.sendKeyEvent($0) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .error(let message):
            errorView(message: message)
        }
    }

    private var disconnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Disconnected")
                .font(.title3)
                .foregroundStyle(.white)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 4)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(spinnerRotation))
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    spinnerRotation = 360
                }
            }

            VStack(spacing: 8) {
                Text(stateDescription)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                Text(connection.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(connection.host):\(connection.port)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var authenticatingView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("Authenticating...")
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Connection Failed")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button {
                vncClient.connect(host: connection.host, port: connection.port)
            } label: {
                Text("Try Again")
                    .fontWeight(.medium)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Status Badge

    private var statusBadge: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text(vncClient.serverName.isEmpty ? connection.displayName : vncClient.serverName)
                        .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding()
            }
            Spacer()
        }
        .opacity(toolbarOpacity)
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 0) {
            // Display mode picker (for multi-monitor)
            Menu {
                ForEach(DisplayMode.allCases, id: \.self) { mode in
                    Button {
                        displayMode = mode
                    } label: {
                        HStack {
                            Text(mode.rawValue)
                            if displayMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: displayMode == .all ? "rectangle.on.rectangle" : "rectangle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }

            Spacer()

            // Input mode picker
            Picker("", selection: $inputMode) {
                Image(systemName: "hand.tap.fill").tag(InputMode.touch)
                Image(systemName: "rectangle.and.hand.point.up.left.fill").tag(InputMode.trackpad)
            }
            .pickerStyle(.segmented)
            .frame(width: 100)

            Spacer()

            // Modifier keys
            HStack(spacing: 4) {
                ModifierKeyButton(symbol: "⌘", keyCode: KeyEvent.command, vncClient: vncClient)
                ModifierKeyButton(symbol: "⌥", keyCode: KeyEvent.alt, vncClient: vncClient)
                ModifierKeyButton(symbol: "⌃", keyCode: KeyEvent.control, vncClient: vncClient)
                ModifierKeyButton(symbol: "⇧", keyCode: KeyEvent.shift, vncClient: vncClient)
            }

            Spacer()

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    isKeyboardActive.toggle()
                } label: {
                    Image(systemName: isKeyboardActive ? "keyboard.fill" : "keyboard")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isKeyboardActive ? .blue : .white)
                        .frame(width: 44, height: 44)
                        .background(isKeyboardActive ? Color.white : Color.white.opacity(0.15))
                        .clipShape(Circle())
                }

                Button {
                    disconnect()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .opacity(toolbarOpacity)
    }

    // MARK: - Actions

    private func handleStateChange(_ state: VNCState) {
        switch state {
        case .authenticating:
            showAuthPrompt = true
        case .connected:
            connectionTimeoutTask?.cancel()
        case .error(let message):
            connectionTimeoutTask?.cancel()
            errorMessage = message
        default:
            break
        }
    }

    private func disconnect() {
        vncClient.disconnect()
        withAnimation {
            isConnected = false
        }
    }

}

// MARK: - Password Prompt View

struct PasswordPromptView: View {
    let serverName: String
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var isSecure = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading) {
                            Text("Enter VNC Password")
                                .font(.headline)
                            Text(serverName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Password") {
                    HStack {
                        if isSecure {
                            SecureField("Enter password", text: $password)
                                .textContentType(.password)
                        } else {
                            TextField("Enter password", text: $password)
                                .textContentType(.password)
                        }
                        Button {
                            isSecure.toggle()
                        } label: {
                            Image(systemName: isSecure ? "eye" : "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        if !password.isEmpty {
                            onSubmit(password)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("Connect")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(password.isEmpty)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        if !password.isEmpty {
                            onSubmit(password)
                        }
                    }
                    .disabled(password.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }
}

// MARK: - Modifier Key Button

struct ModifierKeyButton: View {
    let symbol: String
    let keyCode: UInt32
    @ObservedObject var vncClient: VNCClient

    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed.toggle()
            vncClient.sendKeyEvent(KeyEvent(key: keyCode, isPressed: isPressed))
        } label: {
            Text(symbol)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(isPressed ? .black : .white)
                .frame(width: 40, height: 40)
                .background(isPressed ? Color.white : Color.white.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

#Preview {
    SessionView(
        connection: SavedConnection(name: "Test Mac", host: "192.168.1.100"),
        isConnected: .constant(true)
    )
}
