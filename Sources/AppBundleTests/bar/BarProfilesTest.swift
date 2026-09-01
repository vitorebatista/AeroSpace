@testable import AppBundle
import Foundation
import XCTest

/// Profiles: the visibility rule, its TOML round trip, what it does to the generated config,
/// and what a profile switch costs on a running bar.
final class BarProfilesTest: XCTestCase {
    private let helpers = BarHelperPaths(aerospaceCli: "/opt/homebrew/bin/aerospace-edge")

    private func draft(
        _ items: [String],
        _ profiles: [BarProfile] = [],
        active: String? = nil,
    ) -> BarDraft {
        var draft = BarDraft()
        draft.items = items.map { BarItem(id: $0, cluster: .right) }
        draft.profiles = profiles
        draft.activeProfileName = active
        return draft
    }

    // MARK: - The rule

    func testWithoutProfilesEveryItemIsDrawn() {
        let bar = draft(["clock", "cpu"])
        XCTAssertTrue(bar.isItemVisible("clock", in: nil))
        XCTAssertTrue(bar.isItemVisible("cpu", in: nil))
    }

    func testAnItemIsDrawnUnlessTheActiveProfileHidesIt() {
        let work = BarProfile(name: "Work", workspaces: ["1"], hide: ["weather"])
        let bar = draft(["clock", "weather"], [work])
        XCTAssertTrue(bar.isItemVisible("clock", in: work))
        XCTAssertFalse(bar.isItemVisible("weather", in: work))
    }

    /// The point of `show`. Without it an item wanted on exactly one bar would have to be
    /// listed under `hide` in every other profile.
    func testShowingAnItemInOneProfileHidesItInTheOthers() {
        let work = BarProfile(name: "Work", workspaces: ["1"], show: ["cpu"])
        let play = BarProfile(name: "Play", workspaces: ["2"])
        let bar = draft(["clock", "cpu"], [work, play])
        XCTAssertTrue(bar.isItemVisible("cpu", in: work))
        XCTAssertFalse(bar.isItemVisible("cpu", in: play))
        // The clock is named by neither list, so it stays on both bars.
        XCTAssertTrue(bar.isItemVisible("clock", in: work))
        XCTAssertTrue(bar.isItemVisible("clock", in: play))
    }

    func testAWorkspaceNoProfileNamesDrawsWhatAnyProfileWould() {
        let work = BarProfile(name: "Work", workspaces: ["1"], show: ["cpu"], hide: ["weather"])
        let play = BarProfile(name: "Play", workspaces: ["2"], hide: ["weather"])
        let bar = draft(["cpu", "weather"], [work, play])
        XCTAssertNil(bar.profile(forWorkspace: "9"))
        XCTAssertTrue(bar.isItemVisible("cpu", in: nil), "cpu is on Work's bar, so it is on the shared one")
        XCTAssertFalse(bar.isItemVisible("weather", in: nil), "no profile draws it, so nothing does")
    }

    func testAWorkspaceListedTwiceBelongsToTheProfileWrittenFirst() {
        let bar = draft([], [
            BarProfile(name: "Work", workspaces: ["1", "2"]),
            BarProfile(name: "Play", workspaces: ["2"]),
        ])
        assertEquals(bar.profile(forWorkspace: "2")?.name, "Work")
        assertEquals(bar.profile(forWorkspace: "1")?.name, "Work")
    }

    func testAnActiveProfileNameThatMatchesNothingIsTheSharedBar() {
        let bar = draft(["cpu"], [BarProfile(name: "Work", workspaces: ["1"], show: ["cpu"])], active: "Gone")
        XCTAssertNil(bar.activeProfile)
        XCTAssertTrue(bar.isItemVisible("cpu"))
    }

    // MARK: - Edits

    func testHidingADefaultVisibleItemWritesItToHide() {
        var bar = draft(["clock"], [BarProfile(name: "Work", workspaces: ["1"])])
        bar.setItemVisible("clock", inProfileAt: 0, false)
        assertEquals(bar.profiles[0].hide, ["clock"])
        assertEquals(bar.profiles[0].show, [])
        XCTAssertFalse(bar.isItemVisible("clock", in: bar.profiles[0]))
    }

    func testShowingAnOptInItemWritesItToShow() {
        var bar = draft(["cpu"], [
            BarProfile(name: "Work", workspaces: ["1"], show: ["cpu"]),
            BarProfile(name: "Play", workspaces: ["2"]),
        ])
        bar.setItemVisible("cpu", inProfileAt: 1, true)
        assertEquals(bar.profiles[1].show, ["cpu"])
        // Not also written to `hide`: the file lists only the exception that applies.
        assertEquals(bar.profiles[1].hide, [])
    }

    func testTurningOffTheLastShowMakesTheItemOrdinaryAgain() {
        var bar = draft(["cpu"], [
            BarProfile(name: "Work", workspaces: ["1"], show: ["cpu"]),
            BarProfile(name: "Play", workspaces: ["2"]),
        ])
        bar.setItemVisible("cpu", inProfileAt: 0, false)
        assertEquals(bar.optInItemIds, [])
        assertEquals(bar.profiles[0].hide, ["cpu"], additionalMsg: "the profile that stopped showing it now hides it")
        XCTAssertTrue(bar.isItemVisible("cpu", in: bar.profiles[1]), "and every other profile draws it")
    }

    func testAddedProfilesGetDistinctNames() {
        var bar = BarDraft()
        bar.addProfile()
        bar.addProfile()
        assertEquals(bar.profiles.map(\.name), ["Profile", "Profile 2"])
    }

    // MARK: - bar.toml

    func testProfilesRoundTripByteForByte() {
        let text = """
            version = 1

            [[profile]]
            name = 'Work'          # the day job
            workspaces = ['1', '2', 'C']
            hide = ['weather']

            [[profile]]
            name = 'Play'
            workspaces = ['9']
            show = ['cpu']

            """
        let document = BarTomlDocument(text)
        guard case .success(let draft) = document.draft() else { return XCTFail("Did not parse") }
        assertEquals(draft.profiles.map(\.name), ["Work", "Play"])
        assertEquals(draft.profiles[0].workspaces, ["1", "2", "C"])
        assertEquals(draft.profiles[0].hide, ["weather"])
        assertEquals(draft.profiles[1].show, ["cpu"])

        var written = document
        written.apply(draft, original: draft)
        assertEquals(written.render(), text)
    }

    func testAddingAProfileWritesItWithoutTouchingTheRest() {
        let text = """
            version = 1

            [bar]
            height = 32   # keep this

            [[item]]
            id = 'clock'
            cluster = 'right'

            """
        var document = BarTomlDocument(text)
        guard case .success(let original) = document.draft() else { return XCTFail("Did not parse") }
        var edited = original
        edited.profiles = [BarProfile(name: "Work", workspaces: ["1"], hide: ["clock"])]
        document.apply(edited, original: original)

        let written = document.render()
        XCTAssertTrue(written.contains("height = 32   # keep this"), "An untouched key lost its comment:\n\(written)")
        XCTAssertTrue(written.contains("[[profile]]\nname = 'Work'\nworkspaces = ['1']\nhide = ['clock']"), written)
        // `show` is empty, so it is not written at all: the file lists only the exceptions.
        XCTAssertFalse(written.contains("show ="), written)
    }

    func testAProfileWithoutANameIsRejectedRatherThanDefaulted() {
        let document = BarTomlDocument("[[profile]]\nworkspaces = ['1']\n")
        guard case .failure(let error) = document.draft() else { return XCTFail("Expected a parse failure") }
        XCTAssertTrue(error.description.contains("profile[0]"), error.description)
    }

    func testAProfileListThatIsNotStringsIsRejected() {
        let document = BarTomlDocument("[[profile]]\nname = 'Work'\nworkspaces = [1, 2]\n")
        guard case .failure(let error) = document.draft() else { return XCTFail("Expected a parse failure") }
        XCTAssertTrue(error.description.contains("workspaces[0]"), error.description)
    }

    // MARK: - Generation

    func testWithoutProfilesNoDrawingKeyIsGeneratedAtAll() {
        let config = BarConfigGenerator.generate(draft(["clock"]), helpers: helpers)
        XCTAssertFalse(config.contains("drawing=on"), config)
    }

    func testAHiddenItemIsGeneratedWithItsDrawingOffAndItsScriptNeutered() {
        // `mode` sets `drawing` from its own condition, so leaving its script in place would
        // put it back on screen within a tick of the profile hiding it.
        let bar = draft(
            ["mode", "clock"],
            [BarProfile(name: "Work", workspaces: ["1"], hide: ["mode"])],
            active: "Work",
        )
        let plan = BarConfigGenerator.plan(bar, helpers: helpers)
        let mode = plan.entities.first { $0.name == "aerospace.mode" }
        let clock = plan.entities.first { $0.name == "aerospace.clock" }
        assertEquals(mode?.properties.first { $0.key == "drawing" }?.value, "off")
        assertEquals(mode?.properties.first { $0.key == "script" }?.value, ":")
        assertEquals(clock?.properties.first { $0.key == "drawing" }?.value, "on")
        XCTAssertNotEqual(clock?.properties.first { $0.key == "script" }?.value, ":")
    }

    /// Neutering rather than dropping is what keeps a switch cheap: a dropped property key
    /// forces `BarLiveDiff` to remove and re-add the item.
    func testHidingAndShowingAnItemKeepsTheSamePropertyKeys() {
        let profiles = [
            BarProfile(name: "Work", workspaces: ["1"]),
            BarProfile(name: "Play", workspaces: ["2"], hide: ["mode"]),
        ]
        let shown = BarConfigGenerator.plan(draft(["mode"], profiles, active: "Work"), helpers: helpers)
        let hidden = BarConfigGenerator.plan(draft(["mode"], profiles, active: "Play"), helpers: helpers)
        assertEquals(
            shown.entities.first?.properties.map(\.key),
            hidden.entities.first?.properties.map(\.key),
        )
    }

    func testTheWorkspacesItemListsOnlyTheActiveProfilesWorkspaces() {
        let profile = BarProfile(name: "Work", workspaces: ["1", "a*b"])
        let bar = draft(["workspaces"], [profile], active: "Work")
        let script = BarConfigGenerator.plan(bar, helpers: helpers)
            .entities.first?.properties.first { $0.key == "script" }?.value ?? ""
        // Quoted, so a workspace name holding a glob character is matched literally.
        XCTAssertTrue(script.contains("case \"$w\" in 1|'a*b') ;; *) continue ;; esac;"), script)
    }

    func testTheSharedBarListsEveryWorkspace() {
        let bar = draft(["workspaces"], [BarProfile(name: "Work", workspaces: ["1"])])
        let script = BarConfigGenerator.plan(bar, helpers: helpers)
            .entities.first?.properties.first { $0.key == "script" }?.value ?? ""
        XCTAssertFalse(script.contains("case \"$w\""), script)
    }

    // MARK: - Switching

    /// The whole reason `activeProfileName` lives on the draft: a profile switch is an
    /// ordinary diff, so it cannot describe the bar differently from a save and reload.
    func testASwitchIsOneSetPerItemThatChanged() {
        let profiles = [
            BarProfile(name: "Work", workspaces: ["1"]),
            BarProfile(name: "Play", workspaces: ["2"], hide: ["clock"]),
        ]
        var work = draft(["clock", "cpu"], profiles, active: "Work")
        work.items = [BarItem(id: "clock", cluster: .right), BarItem(id: "cpu", cluster: .left)]
        var play = work
        play.activeProfileName = "Play"

        let commands = BarLiveDiff.commands(from: work, to: play, helpers: helpers)
        assertEquals(commands.count, 1, additionalMsg: "\(commands)")
        assertEquals(commands.first?.first, "--set")
        assertEquals(commands.first?[1], "aerospace.clock")
        XCTAssertTrue(commands.first?.contains("drawing=off") == true, "\(commands)")
        XCTAssertTrue(commands.first?.contains("script=:") == true, "\(commands)")
        // No --add and no --remove: the item stays on the bar, it just stops drawing.
        XCTAssertFalse(commands.contains { $0.first == "--add" || $0.first == "--remove" }, "\(commands)")
    }

    func testSwitchingBackRestoresTheRealScript() {
        let profiles = [
            BarProfile(name: "Work", workspaces: ["1"]),
            BarProfile(name: "Play", workspaces: ["2"], hide: ["clock"]),
        ]
        let work = draft(["clock"], profiles, active: "Work")
        var play = work
        play.activeProfileName = "Play"

        let back = BarLiveDiff.commands(from: play, to: work, helpers: helpers)
        assertEquals(back.count, 1, additionalMsg: "\(back)")
        XCTAssertTrue(back.first?.contains("drawing=on") == true, "\(back)")
        XCTAssertTrue(back.first?.contains { $0.hasPrefix("script=") && $0 != "script=:" } == true, "\(back)")
    }

    func testSwitchingBetweenProfilesThatDrawTheSameItemsCostsNothing() {
        let profiles = [
            BarProfile(name: "Work", workspaces: ["1"]),
            BarProfile(name: "Play", workspaces: ["2"]),
        ]
        let work = draft(["clock"], profiles, active: "Work")
        var play = work
        play.activeProfileName = "Play"
        assertEquals(BarLiveDiff.commands(from: work, to: play, helpers: helpers), [])
    }
}

// MARK: - The controller

@MainActor
final class BarProfileControllerTest: XCTestCase {
    private static let config = """
        [[item]]
        id = 'clock'
        cluster = 'right'

        [[item]]
        id = 'cpu'
        cluster = 'left'

        [[profile]]
        name = 'Work'
        workspaces = ['1']
        hide = ['cpu']

        [[profile]]
        name = 'Play'
        workspaces = ['2']

        """

    private func makeController(
        text: String? = BarProfileControllerTest.config,
        backend: SpyBarBackend = SpyBarBackend(),
    ) -> (BarProfileController, SpyBarBackend) {
        let url = URL(filePath: "/tmp/does-not-exist/bar.toml")
        let controller = BarProfileController(
            configUrl: url,
            backend: backend,
            textReader: { _ in text },
            modificationDate: { _ in text == nil ? nil : Date(timeIntervalSince1970: 1) },
        )
        return (controller, backend)
    }

    private func push(_ controller: BarProfileController, _ workspace: String) async {
        controller.workspaceDidChange(to: workspace)
        // The push is detached so a workspace switch never waits on a process; the tests do.
        await controller.flushPush()
    }

    func testEnteringAProfilesWorkspacePushesIt() async {
        let (controller, backend) = makeController()
        await push(controller, "1")
        assertEquals(backend.pushes.count, 1)
        assertEquals(backend.pushes.first?.previous.activeProfileName, nil)
        assertEquals(backend.pushes.first?.next.activeProfileName, "Work")
    }

    func testStayingInsideOneProfileCostsNoProcess() async {
        let (controller, backend) = makeController()
        await push(controller, "1")
        await push(controller, "1")
        assertEquals(backend.pushes.count, 1, additionalMsg: "A workspace change within one profile must not push")
    }

    func testCrossingIntoAnotherProfileDiffsFromWhatIsOnScreen() async {
        let (controller, backend) = makeController()
        await push(controller, "1")
        await push(controller, "2")
        assertEquals(backend.pushes.count, 2)
        assertEquals(backend.pushes.last?.previous.activeProfileName, "Work")
        assertEquals(backend.pushes.last?.next.activeProfileName, "Play")
    }

    func testAFailedPushLeavesTheBaselineWhereItWas() async {
        let (controller, backend) = makeController(backend: SpyBarBackend(fails: true))
        await push(controller, "1")
        await push(controller, "2")
        assertEquals(backend.pushes.count, 2)
        assertEquals(backend.pushes.last?.previous.activeProfileName, nil, additionalMsg: "The bar never reached Work")
    }

    func testInvalidateForcesTheNextChangeToPushInFull() async {
        let (controller, backend) = makeController()
        await push(controller, "1")
        controller.invalidate()
        await push(controller, "1")
        assertEquals(backend.pushes.count, 2)
        assertEquals(backend.pushes.last?.previous.activeProfileName, nil, additionalMsg: "A reload leaves the shared bar")
    }

    func testAConfigWithNoProfilesNeverPushes() async {
        let (controller, backend) = makeController(text: "[[item]]\nid = 'clock'\ncluster = 'right'\n")
        await push(controller, "1")
        await push(controller, "2")
        assertEquals(backend.pushes.count, 0)
    }

    func testAnUnavailableBarIsNeverPushedTo() async {
        let (controller, backend) = makeController(backend: SpyBarBackend(isAvailable: false))
        await push(controller, "1")
        assertEquals(backend.pushes.count, 0)
    }
}

private final class SpyBarBackend: BarBackend, @unchecked Sendable {
    let isAvailable: Bool
    private let fails: Bool
    private let lock = NSLock()
    private var recorded: [(previous: BarDraft, next: BarDraft)] = []

    init(isAvailable: Bool = true, fails: Bool = false) {
        self.isAvailable = isAvailable
        self.fails = fails
    }

    var pushes: [(previous: BarDraft, next: BarDraft)] { lock.withLock { recorded } }

    func apply(_ draft: BarDraft) throws -> BarApplyOutcome { .updated }

    func applyLive(from previous: BarDraft, to next: BarDraft) throws {
        lock.withLock { recorded.append((previous, next)) }
        if fails { throw BarSettingsError("no bar") }
    }

    func discardLiveChanges() throws {}
}
