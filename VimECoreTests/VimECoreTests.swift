import XCTest
@testable import VimECore

final class LabelsTests: XCTestCase {
    func testCountsAndUniqueness() {
        for n in [0, 1, 2, 13, 14, 15, 100, 500] {
            let labels = Labels.make(count: n)
            XCTAssertEqual(labels.count, n)
            XCTAssertEqual(Set(labels).count, n)
        }
    }

    func testPrefixFree() {
        let labels = Labels.make(count: 300)
        for a in labels {
            for b in labels where a != b {
                XCTAssertFalse(b.hasPrefix(a), "\(a) is a prefix of \(b)")
            }
        }
    }

    func testSingleCharWhenTheyFit() {
        let labels = Labels.make(count: 14)
        XCTAssertTrue(labels.allSatisfy { $0.count == 1 })
        XCTAssertEqual(Labels.make(count: 1).first?.count, 1)
    }

    func testShortLabelsStayShort() {
        // 14 chars: 100 targets should need at most 2 keys.
        XCTAssertTrue(Labels.make(count: 100).allSatisfy { $0.count <= 2 })
    }
}

final class HintSessionTests: XCTestCase {
    func testNarrowThenMatch() {
        var s = HintSession(labels: ["sa", "sd", "f"])
        XCTAssertEqual(s.type("s"), .narrowed)
        XCTAssertTrue(s.isVisible(0))
        XCTAssertFalse(s.isVisible(2))
        XCTAssertEqual(s.type("d"), .matched(1))
    }

    func testTypoIsIgnored() {
        var s = HintSession(labels: ["sa", "sd"])
        _ = s.type("s")
        XCTAssertEqual(s.type("x"), .noMatch)
        XCTAssertEqual(s.typed, "s")
    }

    func testBackspaceAndCase() {
        var s = HintSession(labels: ["sa", "f"])
        _ = s.type("S")
        s.backspace()
        XCTAssertEqual(s.typed, "")
        XCTAssertEqual(s.type("F"), .matched(1))
    }
}

final class KeyRouterTests: XCTestCase {
    let f = KeyInput(keyCode: KeyRouter.fKeyCode, characters: "f")
    var router = KeyRouter()

    func route(_ k: KeyInput, _ mode: Mode = .passthrough, plain: Bool = true,
               editable: Bool = false) -> KeyAction {
        router.route(k, mode: mode, plainKeysAllowed: plain, focusIsEditable: { editable })
    }

    func key(_ c: String, repeat r: Bool = false) -> KeyInput {
        KeyInput(keyCode: 0, characters: c, isRepeat: r)
    }

    func testBareFEntersHintWhenNotTyping() {
        XCTAssertEqual(route(f), .enterHint)
    }

    func testBareFTypesInTextFields() {
        XCTAssertEqual(route(f, editable: true), .pass)
    }

    func testBareFOffInDisabledApps() {
        XCTAssertEqual(route(f, plain: false), .pass)
    }

    func testOptionFWorksEverywhere() {
        var k = f
        k.option = true
        XCTAssertEqual(route(k, plain: false, editable: true), .enterHint)
    }

    func testEditableCheckSkippedForOtherKeys() {
        var called = false
        _ = router.route(key("a"), mode: .passthrough, plainKeysAllowed: true,
                         focusIsEditable: { called = true; return false })
        XCTAssertFalse(called)
    }

    func testShiftFAndCommandFPass() {
        XCTAssertEqual(route(KeyInput(keyCode: 3, characters: "F")), .pass)
        XCTAssertEqual(route(KeyInput(keyCode: 3, characters: "f", command: true)), .pass)
    }

    func testRepeatDoesNotRetriggerHints() {
        XCTAssertEqual(route(KeyInput(keyCode: 3, characters: "f", isRepeat: true)), .pass)
        XCTAssertEqual(route(KeyInput(keyCode: 3, characters: "f", isRepeat: true), .hint), .swallow)
    }

    func testHintModeKeys() {
        XCTAssertEqual(route(KeyInput(keyCode: 53, characters: "\u{1b}"), .hint), .exitHint)
        XCTAssertEqual(route(KeyInput(keyCode: 51, characters: "\u{7f}"), .hint), .backspace)
        XCTAssertEqual(route(KeyInput(keyCode: 1, characters: "s"), .hint), .type("s", .primary))
        XCTAssertEqual(route(KeyInput(keyCode: 18, characters: "1"), .hint), .swallow)
        XCTAssertEqual(route(KeyInput(keyCode: 8, characters: "c", control: true), .hint), .exitHint)
        XCTAssertEqual(route(KeyInput(keyCode: 48, characters: "\t", command: true), .hint), .exitHint)
    }

    func testModifierOnLastLetterPicksClick() {
        XCTAssertEqual(route(KeyInput(keyCode: 1, characters: "S", shift: true), .hint), .type("s", .secondary))
        XCTAssertEqual(route(KeyInput(keyCode: 1, characters: "s", command: true), .hint), .type("s", .command))
        // ⌥ may still be held from ⌥F; it doesn't change the click.
        XCTAssertEqual(route(KeyInput(keyCode: 1, characters: "s", option: true), .hint), .type("s", .primary))
    }

    func testQuestionMarkShowsHelpOutsideTextFields() {
        XCTAssertEqual(route(key("?")), .showHelp)
        XCTAssertEqual(route(key("?"), editable: true), .pass)
        XCTAssertEqual(route(key("?"), plain: false), .pass)
    }

    func testScrollKeys() {
        XCTAssertEqual(route(key("j")), .scroll(.down, isRepeat: false))
        XCTAssertEqual(route(key("k")), .scroll(.up, isRepeat: false))
        XCTAssertEqual(route(key("h")), .scroll(.left, isRepeat: false))
        XCTAssertEqual(route(key("l")), .scroll(.right, isRepeat: false))
        XCTAssertEqual(route(key("d")), .scroll(.halfPageDown, isRepeat: false))
        XCTAssertEqual(route(key("u")), .scroll(.halfPageUp, isRepeat: false))
        XCTAssertEqual(route(key("G")), .scroll(.bottom, isRepeat: false))
    }

    func testHoldingJKeepsScrolling() {
        XCTAssertEqual(route(key("j", repeat: true)), .scroll(.down, isRepeat: true))
    }

    func testScrollKeysTypeInTextFieldsAndDisabledApps() {
        XCTAssertEqual(route(key("j"), editable: true), .pass)
        XCTAssertEqual(route(key("j"), plain: false), .pass)
        XCTAssertEqual(route(KeyInput(keyCode: 38, characters: "j", command: true)), .pass)
    }

    func testGlobalShortcuts() {
        let v = KeyRouter.vKeyCode
        XCTAssertEqual(KeyRouter.globalCommand(KeyInput(keyCode: v, characters: "v", command: true, option: true, control: true)),
                       .toggleEnabled)
        XCTAssertEqual(KeyRouter.globalCommand(KeyInput(keyCode: v, characters: "V", command: true, option: true,
                                                        control: true, shift: true)), .cycleAppRule)
        XCTAssertEqual(KeyRouter.globalCommand(KeyInput(keyCode: v, characters: "v", command: true, option: true,
                                                        control: true, isRepeat: true)), .toggleEnabled)
        XCTAssertNil(KeyRouter.globalCommand(KeyInput(keyCode: v, characters: "v", command: true)))
        XCTAssertNil(KeyRouter.globalCommand(KeyInput(keyCode: v, characters: "v", option: true, control: true)))
        XCTAssertNil(KeyRouter.globalCommand(KeyInput(keyCode: KeyRouter.fKeyCode, characters: "f", command: true,
                                                      option: true, control: true)))
    }

    func testGG() {
        XCTAssertEqual(route(key("g")), .swallow)
        XCTAssertTrue(router.pendingG)
        XCTAssertEqual(route(key("g")), .scroll(.top, isRepeat: false))
        XCTAssertFalse(router.pendingG)
    }

    func testGThenOtherKeyStillWorks() {
        _ = route(key("g"))
        XCTAssertEqual(route(key("j")), .scroll(.down, isRepeat: false))
        XCTAssertEqual(route(key("g")), .swallow)
        XCTAssertEqual(route(key("x")), .pass)
        XCTAssertFalse(router.pendingG)
    }
}

final class ScrollTests: XCTestCase {
    let viewport = CGSize(width: 800, height: 600)

    func testDirections() {
        XCTAssertEqual(ScrollCommand.down.delta(viewport: viewport).dy, -60)
        XCTAssertEqual(ScrollCommand.up.delta(viewport: viewport).dy, 60)
        XCTAssertEqual(ScrollCommand.right.delta(viewport: viewport).dx, -60)
        XCTAssertEqual(ScrollCommand.left.delta(viewport: viewport).dx, 60)
        XCTAssertEqual(ScrollCommand.halfPageDown.delta(viewport: viewport).dy, -300)
        XCTAssertEqual(ScrollCommand.halfPageUp.delta(viewport: viewport).dy, 300)
        XCTAssertGreaterThan(ScrollCommand.top.delta(viewport: viewport).dy, 100_000)
        XCTAssertLessThan(ScrollCommand.bottom.delta(viewport: viewport).dy, -100_000)
    }

    func testStepsSumToTotal() {
        let steps = ScrollCommand.steps(dx: 0, dy: -301, count: 4)
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps.map(\.dy).reduce(0, +), -301)
        XCTAssertEqual(ScrollCommand.steps(dx: 60, dy: 0, count: 1).first?.dx, 60)
    }

    func testJumpToEndIsSplitIntoSafeEvents() {
        let d = ScrollCommand.top.delta(viewport: viewport)
        let n = ScrollCommand.minimumSteps(dx: d.dx, dy: d.dy)
        let steps = ScrollCommand.steps(dx: d.dx, dy: d.dy, count: n)
        XCTAssertTrue(steps.allSatisfy { CGFloat(abs($0.dy)) <= ScrollCommand.maxEventDelta })
        XCTAssertEqual(CGFloat(steps.map(\.dy).reduce(0, +)), d.dy)
        XCTAssertEqual(ScrollCommand.minimumSteps(dx: 0, dy: -60), 1)
    }
}

final class GeometryTests: XCTestCase {
    func testFlipRoundTrip() {
        let ax = CGRect(x: 10, y: 20, width: 30, height: 40)
        let cocoa = Geometry.cocoaRect(fromAX: ax, primaryHeight: 1000)
        XCTAssertEqual(cocoa, CGRect(x: 10, y: 940, width: 30, height: 40))
        XCTAssertEqual(Geometry.axRect(fromCocoa: cocoa, primaryHeight: 1000), ax)
    }

    func testDedupeDropsWrappers() {
        let frames = [
            CGRect(x: 0, y: 0, width: 100, height: 20),
            CGRect(x: 1, y: 0, width: 99, height: 20),   // wrapper of the same button
            CGRect(x: 0, y: 30, width: 100, height: 20), // different button
        ]
        XCTAssertEqual(Geometry.dedupe(frames), [0, 2])
    }

}

final class AppRulesTests: XCTestCase {
    func testDefaultsAndOverrides() {
        var rules = AppRules(fallback: .normal)
        XCTAssertEqual(rules.rule(for: "com.apple.Terminal"), .chordOnly)
        XCTAssertEqual(rules.rule(for: "com.microsoft.VSCode"), .normal)
        XCTAssertEqual(rules.rule(for: nil), .normal)

        rules.set(.off, for: "com.microsoft.VSCode")
        rules.set(.normal, for: "com.apple.Terminal")
        XCTAssertEqual(rules.rule(for: "com.microsoft.VSCode"), .off)
        XCTAssertEqual(rules.rule(for: "com.apple.Terminal"), .normal)
    }

    func testPlainKeysAreOptInByDefault() {
        var rules = AppRules()
        XCTAssertEqual(rules.rule(for: "com.example.SomeGame"), .chordOnly)
        XCTAssertEqual(rules.rule(for: nil), .chordOnly)
        rules.set(.normal, for: "com.apple.finder")
        XCTAssertEqual(rules.rule(for: "com.apple.finder"), .normal)
        XCTAssertEqual(rules.overrides, ["com.apple.finder": .normal])
    }

    func testFallbackChangeReachesUnsetAppsOnly() {
        var rules = AppRules(fallback: .chordOnly)
        rules.set(.off, for: "com.example.SomeGame")
        rules.fallback = .normal
        XCTAssertEqual(rules.rule(for: "com.apple.Safari"), .normal)
        XCTAssertEqual(rules.rule(for: "com.example.SomeGame"), .off)
        XCTAssertEqual(rules.rule(for: "com.apple.Terminal"), .chordOnly)
    }

    func testCycle() {
        var rules = AppRules(fallback: .chordOnly)
        XCTAssertEqual(rules.cycle("com.apple.Safari"), .off)
        XCTAssertEqual(rules.cycle("com.apple.Safari"), .normal)
        XCTAssertEqual(rules.cycle("com.apple.Safari"), .chordOnly)
        XCTAssertEqual(rules.overrides, [:], "back at the default, so nothing is stored")
    }

    func testOnlyDifferencesAreStored() {
        var rules = AppRules(fallback: .normal)
        rules.set(.chordOnly, for: "com.apple.Terminal")  // same as default
        rules.set(.normal, for: "com.apple.Safari")       // same as default
        XCTAssertEqual(rules.overrides, [:])
        rules.set(.off, for: "com.apple.Safari")
        rules.reset("com.apple.Safari")
        XCTAssertEqual(rules.overrides, [:])
    }

    func testRoundTripsThroughPlist() {
        var rules = AppRules()
        rules.set(.off, for: "com.hnc.Discord")
        XCTAssertEqual(AppRules(plist: rules.plist, fallback: rules.fallback), rules)
        XCTAssertEqual(AppRules(plist: ["a": "bogus"]).overrides, [:])
    }

    func testListedIncludesDefaultsAndOverrides() {
        var rules = AppRules()
        rules.set(.off, for: "com.hnc.Discord")
        XCTAssertTrue(rules.listed.contains("com.hnc.Discord"))
        XCTAssertTrue(rules.listed.contains("com.apple.Terminal"))
    }

    func testChromiumDetection() {
        XCTAssertTrue(Policy.isChromiumBrowser(bundleID: "com.google.Chrome", frameworks: ["Google Chrome Framework.framework"]))
        XCTAssertTrue(Policy.isChromiumBrowser(bundleID: "company.thebrowser.Browser", frameworks: []))
        XCTAssertFalse(Policy.isChromiumBrowser(bundleID: "com.hnc.Discord",
                                                frameworks: ["Electron Framework.framework", "Squirrel.framework"]))
        XCTAssertFalse(Policy.isChromiumBrowser(bundleID: "com.apple.Safari", frameworks: []))
    }
}

final class HintRulesTests: XCTestCase {
    let window = CGRect(x: 0, y: 0, width: 1000, height: 800)
    var root: HintRules.Context { HintRules.Context(clip: window, rootArea: 1000 * 800) }
    let small = CGRect(x: 10, y: 10, width: 80, height: 20)

    func testControlsAndPressables() {
        XCTAssertEqual(HintRules.decide(role: "AXButton", visible: small, context: root), .target)
        XCTAssertEqual(HintRules.decide(role: "AXGroup", visible: small, context: root), .ifPressable)
        XCTAssertEqual(HintRules.decide(role: "AXStaticText", visible: small, context: root), .notTarget)
        XCTAssertEqual(HintRules.decide(role: "AXMenuItem", visible: small, enabled: false, context: root), .notTarget)
        XCTAssertEqual(HintRules.decide(role: "AXButton", visible: CGRect(x: 0, y: 0, width: 6, height: 300),
                                        context: root), .notTarget)
    }

    func testPageSizedContainerIsNoise() {
        XCTAssertEqual(HintRules.decide(role: "AXGroup", visible: window, context: root), .notTarget)
        // A big real control still counts.
        XCTAssertEqual(HintRules.decide(role: "AXTextArea", visible: window, context: root), .target)
    }

    func testRowsGetOneHint() {
        let row = HintRules.childContext(role: "AXRow", visible: small, context: root)
        XCTAssertEqual(HintRules.decide(role: "AXRow", visible: small, context: root), .target)
        for part in ["AXCell", "AXTextField", "AXStaticText", "AXImage", "AXDisclosureTriangle"] {
            XCTAssertEqual(HintRules.decide(role: part, visible: small, context: row), .notTarget, part)
        }
        // Real controls inside a row still get their own.
        XCTAssertEqual(HintRules.decide(role: "AXCheckBox", visible: small, context: row), .target)
    }

    func testWebDataTablesNeedAPressAction() {
        let web = HintRules.childContext(role: "AXWebArea", visible: window, context: root)
        let table = HintRules.childContext(role: "AXTable", visible: window, context: web)
        XCTAssertEqual(HintRules.decide(role: "AXRow", visible: small, context: table), .ifPressable)
        XCTAssertEqual(HintRules.decide(role: "AXCell", visible: small, context: table), .ifPressable)
        // A web tree (VS Code's file list) is an outline, not a table.
        let outline = HintRules.childContext(role: "AXOutline", visible: window, context: web)
        XCTAssertEqual(HintRules.decide(role: "AXRow", visible: small, context: outline), .target)
    }

    func testScrollAreasClipTheirContents() {
        let area = CGRect(x: 0, y: 100, width: 1000, height: 300)
        let inside = HintRules.childContext(role: "AXScrollArea", visible: area, context: root)
        // Scrolled up out of view (but still on screen, behind the toolbar).
        XCTAssertNil(HintRules.visibleRect(role: "AXRow", frame: CGRect(x: 0, y: 40, width: 1000, height: 20),
                                           context: inside))
        // Half visible: the hint goes on the visible part.
        XCTAssertEqual(HintRules.visibleRect(role: "AXRow", frame: CGRect(x: 0, y: 390, width: 1000, height: 20),
                                             context: inside), CGRect(x: 0, y: 390, width: 1000, height: 10))
    }

    func testMenusEscapeTheirParentsClip() {
        let bar = HintRules.Context(clip: CGRect(x: 0, y: 0, width: 1000, height: 24), rootArea: 24_000)
        let menu = CGRect(x: 10, y: 24, width: 200, height: 300)
        XCTAssertEqual(HintRules.visibleRect(role: "AXMenu", frame: menu, context: bar), menu)
        XCTAssertNil(HintRules.visibleRect(role: "AXGroup", frame: menu, context: bar))
    }

    func testClosedMenusAndScrollBarsAreSkipped() {
        XCTAssertTrue(HintRules.isHidden(role: "AXMenu", hasFrame: false))
        XCTAssertFalse(HintRules.isHidden(role: "AXMenu", hasFrame: true))
        XCTAssertTrue(HintRules.isHidden(role: "AXScrollBar", hasFrame: true))
        XCTAssertFalse(HintRules.isHidden(role: "AXGroup", hasFrame: false))
    }

    func testLeaves() {
        XCTAssertTrue(HintRules.isLeaf(role: "AXLink", visible: small))
        XCTAssertFalse(HintRules.isLeaf(role: "AXLink", visible: CGRect(x: 0, y: 0, width: 300, height: 300)))
        // Tabs hold their own close buttons.
        XCTAssertFalse(HintRules.isLeaf(role: "AXRadioButton", visible: small))
    }
}

final class VisibilityTests: XCTestCase {
    let item = CGRect(x: 115, y: 0, width: 42, height: 33)

    func testAutoHiddenMenuBarHidesItsItems() {
        let hidden = CGRect(x: 0, y: -33, width: 1728, height: 33)
        XCTAssertFalse(Visibility.isMenuBarItemShown(item, shownBars: [hidden]))
    }

    func testShownMenuBarKeepsItsItems() {
        let shown = CGRect(x: 0, y: 0, width: 1728, height: 33)
        XCTAssertTrue(Visibility.isMenuBarItemShown(item, shownBars: [shown]))
    }

    func testSecondDisplay() {
        let primaryHidden = CGRect(x: 0, y: -33, width: 1728, height: 33)
        let secondShown = CGRect(x: 1728, y: 0, width: 2560, height: 33)
        let onSecond = CGRect(x: 1800, y: 0, width: 40, height: 33)
        XCTAssertTrue(Visibility.isMenuBarItemShown(onSecond, shownBars: [primaryHidden, secondShown]))
        XCTAssertFalse(Visibility.isMenuBarItemShown(item, shownBars: [primaryHidden, secondShown]))
    }

    func testUnknownBarsKeepItems() {
        XCTAssertTrue(Visibility.isMenuBarItemShown(item, shownBars: []))
    }
}
