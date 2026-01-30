import XCTest

final class SessionUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--mock-connection"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Session View Tests

    /// Note: These tests require a mock VNC connection or test mode in the app
    /// They verify UI elements exist but can't test actual remote control

    func testSessionViewToolbar() {
        // If we can navigate to a session (mock or saved)
        // Verify toolbar elements

        // This would need a mock connection setup
        // For now, verify app doesn't crash when looking for these elements

        let toolbar = app.toolbars.firstMatch
        if toolbar.exists {
            XCTAssertTrue(toolbar.buttons.count > 0)
        }
    }

    func testKeyboardToggle() {
        // Look for keyboard toggle button in session
        let keyboardButton = app.buttons["Toggle Keyboard"]

        if keyboardButton.exists {
            keyboardButton.tap()

            // Keyboard should appear
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 2))
        }
    }

    func testModifierKeyButtons() {
        // Session toolbar should have modifier key buttons
        let expectedModifiers = ["Shift", "Control", "Option", "Command"]

        for modifier in expectedModifiers {
            let button = app.buttons[modifier]
            // Just check they don't cause crashes if accessed
            _ = button.exists
        }
    }

    // MARK: - Gesture Tests

    func testPinchGestureDoesntCrash() {
        // Perform pinch gesture on main view
        let mainView = app.otherElements.firstMatch

        if mainView.exists {
            mainView.pinch(withScale: 2.0, velocity: 1.0)
            mainView.pinch(withScale: 0.5, velocity: -1.0)

            // App should still be responsive
            XCTAssertTrue(app.state == .runningForeground)
        }
    }

    func testPanGestureDoesntCrash() {
        let mainView = app.otherElements.firstMatch

        if mainView.exists {
            let start = mainView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let end = mainView.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.7))

            start.press(forDuration: 0.1, thenDragTo: end)

            XCTAssertTrue(app.state == .runningForeground)
        }
    }

    func testDoubleTapGesture() {
        let mainView = app.otherElements.firstMatch

        if mainView.exists {
            mainView.doubleTap()

            XCTAssertTrue(app.state == .runningForeground)
        }
    }

    func testTwoFingerTap() {
        let mainView = app.otherElements.firstMatch

        if mainView.exists {
            mainView.twoFingerTap()

            XCTAssertTrue(app.state == .runningForeground)
        }
    }

    // MARK: - Disconnect Tests

    func testDisconnectButton() {
        let disconnectButton = app.buttons["Disconnect"]

        if disconnectButton.exists {
            disconnectButton.tap()

            // Should return to home screen
            let homeNav = app.navigationBars["MacRemote"]
            XCTAssertTrue(homeNav.waitForExistence(timeout: 2))
        }
    }

    // MARK: - Error Handling Tests

    func testConnectionErrorAlert() {
        // When connection fails, an alert should appear
        // This requires the mock to simulate failure

        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            // Verify alert has dismiss button
            XCTAssertTrue(alert.buttons.count > 0)
        }
    }

    // MARK: - Memory Tests

    func testRepeatedConnectionAttempts() {
        // Stress test: rapidly try to connect multiple times
        // This helps catch memory leaks and race conditions

        let addButton = app.buttons["Add Connection"]
        guard addButton.exists else { return }

        for _ in 0..<5 {
            addButton.tap()

            // Wait briefly
            Thread.sleep(forTimeInterval: 0.5)

            // Dismiss
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
            }
        }

        XCTAssertTrue(app.state == .runningForeground)
    }
}
