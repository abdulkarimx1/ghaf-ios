import XCTest

/// Exhaustive screen sweep: for one tab (GHAF_SWEEP_TAB 0–4), taps every button/cell (level 1) from a fresh launch,
/// then every button/cell on the screen it opens (level 2), snapping each screen and flagging taps that change nothing.
/// Data is the in-memory fixture restored from GHAF_BACKUP, so destructive buttons are safe; each L1 starts fresh.
final class GhafSweepTests: XCTestCase {
    let out = ProcessInfo.processInfo.environment["GHAF_UI_OUT"] ?? NSTemporaryDirectory()
    let tab = Int(ProcessInfo.processInfo.environment["GHAF_SWEEP_TAB"] ?? "0") ?? 0
    var app: XCUIApplication!
    var report = ""
    var shot = 0

    override func setUp() {
        continueAfterFailure = true
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? report.write(toFile: "\(out)/sweep-tab\(tab).tsv", atomically: true, encoding: .utf8)
    }

    func launchToTab() {
        app = XCUIApplication()
        let backup = ProcessInfo.processInfo.environment["GHAF_BACKUP"].map { ["-GhafRestoreBackup", $0] } ?? []
        app.launchArguments = ["-GhafFixture", "1"] + backup + ["-GhafTheme", "Graphite", "-GhafAppearance", "Dark", "-GhafLanguage", "en"]
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 25)
        let b = app.tabBars.buttons.element(boundBy: tab)
        if b.exists { b.tap() }
        sleep(1)
    }

    @discardableResult func snap(_ name: String) -> String {
        shot += 1
        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression).prefix(40)
        let file = String(format: "t%d-%03d-%@.png", tab, shot, String(safe))
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "\(out)/\(file)"))
        return file
    }

    /// Cheap fingerprint of what's on screen: visible texts and the nav title.
    func signature() -> String {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).filter { $0.isHittable }.map(\.label)
        return (app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.identifier : "") + "|" + texts.joined(separator: "·")
    }

    /// Labels of tappable things on the current screen (scrolling through it), excluding the tab bar.
    func collectTargets(maxScrolls: Int, skip: Set<String>) -> [String] {
        var seen: [String] = []
        let tabFrame = app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .zero
        for step in 0...maxScrolls {
            let query = app.descendants(matching: .any).matching(NSPredicate(format: "elementType IN %@",
                [XCUIElement.ElementType.button.rawValue, XCUIElement.ElementType.cell.rawValue,
                 XCUIElement.ElementType.switch.rawValue, XCUIElement.ElementType.segmentedControl.rawValue,
                 XCUIElement.ElementType.link.rawValue]))
            for e in query.allElementsBoundByIndex.prefix(80) where e.exists && e.isHittable {
                let label = e.label.isEmpty ? e.identifier : e.label
                guard !label.isEmpty, !skip.contains(label), !seen.contains(label), !tabFrame.contains(e.frame) else { continue }
                seen.append(label)
            }
            if step < maxScrolls { app.swipeUp(velocity: 900) }
        }
        return seen
    }

    func find(_ label: String, scrolls: Int) -> XCUIElement? {
        for i in 0...scrolls {
            let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR identifier == %@", label, label)).firstMatch
            if e.exists && e.isHittable { return e }
            if i < scrolls { app.swipeUp(velocity: 900) }
        }
        return nil
    }

    func goBack() {
        if app.navigationBars.buttons.firstMatch.exists && app.navigationBars.buttons.firstMatch.isHittable {
            app.navigationBars.buttons.firstMatch.tap(); sleep(1); return
        }
        for name in ["Back", "Close", "Cancel", "Done", "Not now"] {
            let b = app.buttons[name].firstMatch
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
        app.swipeDown(velocity: 1500); sleep(1)
    }

    func row(_ level: String, _ path: String, _ result: String, _ file: String) {
        report += "\(level)\t\(path)\t\(result)\t\(file)\n"
        try? report.write(toFile: "\(out)/sweep-tab\(tab).tsv", atomically: true, encoding: .utf8)
    }

    func testSweepTab() {
        launchToTab()
        snap("root")
        for i in 1...4 { app.swipeUp(velocity: 900); snap("root-scroll\(i)") }
        launchToTab()
        let rootSig = signature()
        let l1 = collectTargets(maxScrolls: 4, skip: [])
        row("ROOT", "targets=\(l1.count)", l1.joined(separator: " | "), "")

        for target in l1 {
            launchToTab()
            guard let e = find(target, scrolls: 4) else { row("L1", target, "NOT-FOUND", ""); continue }
            let before = signature()
            e.tap(); sleep(1)
            let after = signature()
            let file = snap("L1-\(target)")
            let changed = after != before
            row("L1", target, changed ? "opened" : "NO-CHANGE", file)
            guard changed, after != rootSig else { continue }
            for k in 1...2 { app.swipeUp(velocity: 900); snap("L1-\(target)-scroll\(k)") }
            app.swipeDown(velocity: 1500); app.swipeDown(velocity: 1500)

            let l2 = collectTargets(maxScrolls: 2, skip: Set(l1)).prefix(30)
            let l1Sig = signature()
            for sub in l2 {
                if signature() != l1Sig {
                    launchToTab()
                    guard let again = find(target, scrolls: 4) else { break }
                    again.tap(); sleep(1)
                }
                guard let s = find(sub, scrolls: 2) else { row("L2", "\(target) › \(sub)", "NOT-FOUND", ""); continue }
                let b2 = signature()
                s.tap(); sleep(1)
                let a2 = signature()
                let f2 = snap("L2-\(target)-\(sub)")
                row("L2", "\(target) › \(sub)", a2 != b2 ? "opened" : "NO-CHANGE", f2)
                if a2 != b2 { goBack() }
            }
        }
    }
}
