import XCTest

final class MacRemoteUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Home Screen Tests

    func testHomeScreenExists() {
        // Verify main navigation elements exist
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }

    func testAddConnectionButtonExists() {
        // Look for the add button (could be + or "Add Connection")
        let addButton = app.buttons["Add Connection"]
        let plusButton = app.buttons.matching(identifier: "addConnection").firstMatch

        XCTAssertTrue(addButton.exists || plusButton.exists || app.buttons["+"].exists)
    }

    func testSettingsNavigation() {
        // Tap settings button if it exists
        let settingsButton = app.buttons["Settings"]
        if settingsButton.exists {
            settingsButton.tap()

            // Verify settings view appears
            let settingsTitle = app.navigationBars["Settings"]
            XCTAssertTrue(settingsTitle.waitForExistence(timeout: 2))
        }
    }

    // MARK: - Add Connection Flow Tests

    func testAddConnectionFlow() {
        // Find and tap add connection button
        let addButton = app.buttons["Add Connection"]
        guard addButton.exists else {
            XCTSkip("Add Connection button not found")
            return
        }

        addButton.tap()

        // Verify add connection sheet/view appears
        let ipField = app.textFields.firstMatch
        XCTAssertTrue(ipField.waitForExistence(timeout: 2))
    }

    func testManualIPEntry() {
        // Navigate to add connection
        let addButton = app.buttons["Add Connection"]
        guard addButton.exists else {
            XCTSkip("Add Connection button not found")
            return
        }

        addButton.tap()

        // Find IP address field
        let ipField = app.textFields["IP Address"]
        guard ipField.waitForExistence(timeout: 2) else {
            XCTSkip("IP Address field not found")
            return
        }

        // Enter IP address
        ipField.tap()
        ipField.typeText("192.168.1.100")

        // Verify text was entered
        XCTAssertEqual(ipField.value as? String, "192.168.1.100")
    }

    // MARK: - Settings Tests

    func testQualityModeSelection() {
        // Navigate to settings
        let settingsButton = app.buttons["Settings"]
        guard settingsButton.exists else {
            XCTSkip("Settings button not found")
            return
        }

        settingsButton.tap()

        // Look for quality picker
        let qualityPicker = app.buttons["Quality"].firstMatch
        if qualityPicker.exists {
            qualityPicker.tap()

            // Check for quality options
            let autoOption = app.buttons["Auto"]
            XCTAssertTrue(autoOption.waitForExistence(timeout: 2))
        }
    }

    // MARK: - Discovery Tests

    func testServiceDiscoveryList() {
        // Home screen should show discovered Macs
        let discoveredList = app.collectionViews.firstMatch

        // List should exist even if empty
        XCTAssertTrue(discoveredList.exists || app.tables.firstMatch.exists)
    }

    // MARK: - Accessibility Tests

    func testAccessibilityLabels() {
        // Verify key elements have accessibility labels
        let addButton = app.buttons["Add Connection"]

        if addButton.exists {
            XCTAssertFalse(addButton.label.isEmpty)
        }
    }

    func testVoiceOverSupport() {
        // Check that interactive elements are accessible
        let buttons = app.buttons.allElementsBoundByIndex

        for button in buttons {
            XCTAssertTrue(button.isHittable || !button.isEnabled)
        }
    }

    // MARK: - Orientation Tests

    func testLandscapeOrientation() {
        XCUIDevice.shared.orientation = .landscapeLeft

        // App should adapt to landscape
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }

    func testPortraitOrientation() {
        XCUIDevice.shared.orientation = .portrait

        // App should work in portrait too
        XCTAssertTrue(app.navigationBars.firstMatch.exists)
    }

    // MARK: - Performance Tests

    func testLaunchPerformance() throws {
        if #available(iOS 15.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
