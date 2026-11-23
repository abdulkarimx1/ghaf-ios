import XCTest

/// Reproducible navigation and scroll workload for the assigned Ghaf-A simulator.
/// Owner data is restored into the DEBUG in-memory fixture and is never written to disk.
final class GhafTabSpeedTests: XCTestCase {
    private var app: XCUIApplication!

    func testTabCycleAndScrolling() throws {
        try runScenario(appearance: "Dark", language: "en", cycles: 5)
    }

    func testOtherAppearanceAndLanguageBaselines() throws {
        try runScenario(appearance: "Light", language: "en", cycles: 1)
        try runScenario(appearance: "Dark", language: "ar", cycles: 1)
        try runScenario(appearance: "Light", language: "ar", cycles: 1)
    }

    private func runScenario(appearance: String, language: String, cycles: Int) throws {
        app = XCUIApplication()
        let backup = ProcessInfo.processInfo.environment["TEST_RUNNER_GHAF_BACKUP"].map { ["-GhafRestoreBackup", $0] } ?? []
        app.launchArguments = ["-GhafFixture", "1", "-GhafExportSpeedSignposts"] + backup + ["-GhafTheme", "Graphite", "-GhafAppearance", appearance, "-GhafLanguage", language]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))

        let tabs: [(index: Int, name: String)] = [(1, "Transactions"), (3, "Stats"), (4, "More"), (0, "Home")]
        var shot = 0
        for cycle in 1...cycles {
            for (index, name) in tabs {
                let tab = app.tabBars.buttons.element(boundBy: index)
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing tab at index: \(index)")
                tab.tap()
                assertWithinMeasuredBudget(tab: index, name: name)
                shot += 1
                capture("\(appearance)-\(language)-cycle\(cycle)-\(name)", index: shot)
                exportSignpostReport(appearance: appearance, language: language, cycle: cycle, step: name)
            }
            app.swipeUp(velocity: .fast)
            shot += 1
            capture("\(appearance)-\(language)-cycle\(cycle)-scroll", index: shot)
            app.tabBars.buttons.element(boundBy: 1).tap()
            app.swipeUp(velocity: .fast)
            app.swipeUp(velocity: .fast)
            shot += 1
            capture("\(appearance)-\(language)-cycle\(cycle)-transactions-scroll", index: shot)
            app.tabBars.buttons.element(boundBy: 0).tap()
            app.swipeUp(velocity: .fast)
            shot += 1
            capture("\(appearance)-\(language)-cycle\(cycle)-home-scroll", index: shot)
        }
        app.terminate()
    }

    private func assertWithinMeasuredBudget(tab: Int, name: String) {
        let report = app.staticTexts["ghaf.speed.report"]
        guard report.waitForExistence(timeout: 3) else {
            XCTFail("Missing DEBUG signpost report after opening \(name)")
            return
        }
        let tabTag = [0: 0, 1: 3, 3: 2, 4: 4][tab] ?? tab
        let latest = report.label.split(separator: ",").compactMap { entry -> (Int, Double)? in
            let fields = entry.split(separator: ":")
            guard fields.count == 3, let reportTab = Int(fields[0]), let milliseconds = Double(fields[2]) else { return nil }
            return (reportTab, milliseconds)
        }.last { $0.0 == tabTag }
        guard let measured = latest?.1 else {
            XCTFail("No signpost duration reported for \(name)")
            return
        }

        // Post-fix median selection-to-appearance intervals in milliseconds, including the
        // native tab transition. Median excludes the initial warm visit and tap scheduling jitter.
        let postFixBaseline: [Int: Double] = [3: 249.85, 2: 239.69, 4: 272.75, 0: 240.70]
        guard let baseline = postFixBaseline[tabTag] else { return }
        XCTAssertLessThanOrEqual(measured, baseline * 2,
                                 "\(name) took \(measured) ms; budget is \(baseline * 2) ms")
    }

    private func exportSignpostReport(appearance: String, language: String, cycle: Int, step: String) {
        let report = app.staticTexts["ghaf.speed.report"]
        guard report.waitForExistence(timeout: 3) else { return }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("speed-signposts-\(appearance)-\(language).txt")
        let line = "cycle=\(cycle),step=\(step),report=\(report.label)\n"
        if let handle = try? FileHandle(forWritingTo: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8) ?? Data())
            try? handle.close()
        } else { try? line.write(to: path, atomically: true, encoding: .utf8) }
    }

    private func capture(_ name: String, index: Int) {
        let image = XCUIScreen.main.screenshot().pngRepresentation
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(String(format: "%03d-%@.png", index, name))
        try? image.write(to: path)
    }
}
