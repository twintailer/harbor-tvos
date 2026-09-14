import XCTest

/// Runs against the real app and tvOS focus engine, not just the navigation policy.
final class NavigationUITests: XCTestCase {
    private var app: XCUIApplication!
    private let remote = XCUIRemote.shared

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-fixtures"]
        app.launch()
        assertTab("home")
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app.terminate()
    }

    func testTabsSwitchOnFocusAndDoNotBounceHome() {
        // Never press Select: moving focus must select each page immediately.
        for section in ["series", "movies", "anime", "catalogs", "library"] {
            remote.press(.right)
            assertTab(section)
            assertStaysAwayFromHome()
        }
        remote.press(.right) // More is a menu, not an automatic page change.
        XCTAssertEqual(app.buttons["navigation.library"].value as? String, "Selected")
        remote.press(.right)
        assertTab("settings")
        assertStaysAwayFromHome()
        remote.press(.left) // More
        for section in ["library", "catalogs", "anime", "movies", "series", "home", "search"] {
            remote.press(.left)
            assertTab(section)
        }
    }

    func testBackFromSearchContentReturnsToHarborThenHomeExits() {
        remote.press(.left)
        assertTab("search")
        remote.press(.down)
        XCTAssertFalse(app.buttons["navigation.search"].hasFocus, "Exercise Back from search content")
        remote.press(.menu)
        assertTab("home")
        XCTAssertEqual(app.state, .runningForeground)
        remote.press(.menu)
        waitUntil("Only Harbor Home allows the app to leave the foreground") {
            self.app.state != .runningForeground
        }
    }

    func testBackFromEveryVisibleTabReturnsToHarborHome() {
        for steps in 1...7 where steps != 6 { // More is a menu, not a destination.
            for _ in 0..<steps { remote.press(.right) }
            XCTAssertNotEqual(app.buttons["navigation.home"].value as? String, "Selected")
            remote.press(.menu)
            assertTab("home")
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    func testSettingsDestinationSurvivesAndBackPopsOnlyOneLevel() {
        for _ in 0..<7 { remote.press(.right) }
        assertTab("settings")
        focus(app.buttons["settings.route.player"])
        remote.press(.select)
        waitUntil("A settings panel hides the main navigation") {
            !self.app.buttons["navigation.settings"].exists
        }
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["navigation.settings"].exists
        }, object: nil)
        reset.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 2), .completed,
                       "Opening a detail must not rebuild and pop the navigation stack")
        remote.press(.menu)
        waitUntil("Back returns to the Settings dashboard") {
            self.app.buttons["navigation.settings"].value as? String == "Selected"
        }
        XCTAssertEqual(app.state, .runningForeground)
        remote.press(.menu)
        assertTab("home")
    }

    func testTopBarDoesNotOverlapPageContent() {
        for (section, title) in [("series", "Series"), ("movies", "Movies"), ("anime", "Anime"), ("catalogs", "Catalogs")] {
            remote.press(.right)
            assertTab(section)
            let heading = app.staticTexts["page.title.\(title)"]
            XCTAssertTrue(heading.waitForExistence(timeout: 10))
            XCTAssertGreaterThan(heading.frame.minY, app.buttons["navigation.\(section)"].frame.maxY,
                                 "Content must occupy its own region below navigation")
        }
        capture("Catalogs below navigation")
    }

    func testSpotlightAutoRotatesAndAllowsManualSelection() {
        let position = app.staticTexts["spotlight.position"]
        XCTAssertTrue(position.waitForExistence(timeout: 10))
        let initial = position.label
        waitUntil("Spotlight advances automatically while navigation owns focus") { position.label != initial }
        let page = app.buttons["spotlight.page.4"]
        focus(page)
        waitUntil("Focusing a carousel indicator selects its title") { position.label == "5 / 10" }
        capture("Top 10 spotlight")
        let change = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in position.label != "5 / 10" }, object: nil)
        change.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [change], timeout: 9), .completed,
                       "Manual focus pauses autoplay so Select cannot open an unexpected title")
    }

    func testViewAllOpensFullScreenGridAndReturnsToCatalogs() {
        for _ in 0..<4 { remote.press(.right) }
        assertTab("catalogs")
        let all = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog.viewAll.")).firstMatch
        focus(all)
        remote.press(.select)
        let back = app.buttons["catalog.grid.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation.catalogs"].exists)
        let first = app.buttons["poster.movie:fixture1"]
        let nextRow = app.buttons["poster.movie:fixture7"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(nextRow.exists)
        XCTAssertGreaterThan(nextRow.frame.minY, first.frame.minY, "View all uses multiple rows, not a horizontal rail")
        capture("Full screen catalog grid")
        focus(first)
        remote.press(.select)
        XCTAssertTrue(app.buttons["detail.play"].waitForExistence(timeout: 10))
        remote.press(.menu)
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back from a title restores View all first")
        XCTAssertFalse(app.buttons["navigation.catalogs"].exists)
        remote.press(.menu)
        waitUntil("Back restores the catalog screen") {
            self.app.buttons["navigation.catalogs"].value as? String == "Selected"
        }
        remote.press(.menu)
        assertTab("home")
    }

    func testPlayerMoreMenuAndNestedBack() {
        app.terminate()
        app.launchArguments = ["--ui-fixtures", "--ui-player"]
        app.launch()
        let play = app.descendants(matching: .any)["player.control.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        capture("Player controls")
        for _ in 0..<4 { remote.press(.right) }
        remote.press(.select)
        let title = app.staticTexts["player.panel.title"]
        waitUntil("More opens playback settings") { title.label == "Playback settings" }
        capture("Player settings")
        remote.press(.select)
        waitUntil("Speed opens a nested panel") { title.label == "Playback Speed" }
        remote.press(.menu)
        waitUntil("Back returns one level to More") { title.label == "Playback settings" }
        remote.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func capture(_ name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertTab(_ section: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.buttons["navigation.\(section)"]
        waitUntil("\(section) is selected and retains remote focus", file: file, line: line) {
            tab.exists && tab.hasFocus && tab.value as? String == "Selected"
        }
    }

    private func assertStaysAwayFromHome() {
        let reset = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["navigation.home"].value as? String == "Selected"
        }, object: nil)
        reset.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [reset], timeout: 1), .completed)
    }

    private func focus(_ target: XCUIElement) {
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        for _ in 0..<20 {
            if target.hasFocus { return }
            let current = app.descendants(matching: .any)
                .matching(NSPredicate(format: "hasFocus == true")).firstMatch
            XCTAssertTrue(current.exists, "Expected a focused control")
            let from = current.frame
            let to = target.frame
            if from.maxY < to.minY {
                remote.press(.down)
            } else if from.minY > to.maxY {
                remote.press(.up)
            } else {
                remote.press(from.midX < to.midX ? .right : .left)
            }
        }
        XCTFail("Could not focus \(target.identifier)")
    }

    private func waitUntil(_ message: String, file: StaticString = #filePath, line: UInt = #line,
                           condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed,
                       message, file: file, line: line)
    }
}
