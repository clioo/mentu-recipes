import XCTest
@testable import MentuRecipesCore

final class ProgressRenderTests: XCTestCase {

    private let plain = ProgressRender.Palette.plain

    /// Glyph + space + counter + label + engine + elapsed + two spaces. Every
    /// step line hands the outcome field over at exactly this offset.
    private var outcomeOffset: Int {
        1 + 1 + ProgressRender.Col.counter + ProgressRender.Col.label
            + ProgressRender.Col.engine + ProgressRender.Col.elapsed + 2
    }

    func testStateVocabularyIsExactlyFiveGlyphs() {
        let glyphs = ProgressRender.State.allCases.map(\.glyph)
        XCTAssertEqual(glyphs, ["\u{23F8}", "\u{23F5}", "\u{2713}", "\u{2717}", "\u{2298}"])
        XCTAssertEqual(Set(glyphs).count, 5)
    }

    func testBarIsFixedWidthAndCarriesThePercent() {
        for (done, total) in [(0, 2), (1, 2), (2, 2), (3, 17), (99, 100)] {
            let rendered = ProgressRender.bar(done: done, total: total, palette: plain)
            let cells = rendered.prefix { $0 == "\u{2588}" || $0 == "\u{2591}" }
            XCTAssertEqual(cells.count, ProgressRender.Col.bar, "done=\(done) total=\(total)")
        }
        XCTAssertTrue(ProgressRender.bar(done: 1, total: 2, palette: plain).hasSuffix(" 50%"))
        XCTAssertTrue(ProgressRender.bar(done: 0, total: 5, palette: plain).hasSuffix("  0%"))
        XCTAssertTrue(ProgressRender.bar(done: 5, total: 5, palette: plain).hasSuffix("100%"))
    }

    func testBarToleratesZeroTotalAndOutOfRangeCounts() {
        XCTAssertTrue(ProgressRender.bar(done: 0, total: 0, palette: plain).hasSuffix("  0%"))
        XCTAssertTrue(ProgressRender.bar(done: 9, total: 2, palette: plain).hasSuffix("100%"))
        XCTAssertTrue(ProgressRender.bar(done: -3, total: 2, palette: plain).hasSuffix("  0%"))
    }

    func testEveryStepLineHandsOffToTheOutcomeAtTheSameColumn() {
        let lines = [
            ProgressRender.stepLine(state: .running, index: 1, total: 2, label: "produce",
                                    engine: "shell", elapsed: "3s", outcome: "running", palette: plain),
            ProgressRender.stepLine(state: .ok, index: 12, total: 99, label: "a-longer-step-label",
                                    engine: "codex-cli", elapsed: "1h07m", outcome: "ok", palette: plain),
            ProgressRender.stepLine(state: .failed, index: 3, total: 4, label: "x",
                                    engine: "", elapsed: "", outcome: "exit 1", palette: plain)
        ]
        let outcomes = ["running", "ok", "exit 1"]
        for (line, outcome) in zip(lines, outcomes) {
            XCTAssertEqual(line.count, outcomeOffset + outcome.count, "line: \(line)")
            XCTAssertEqual(String(line.suffix(outcome.count)), outcome)
        }
        // Fields land where the columns say they do.
        let first = Array(lines[0])
        XCTAssertEqual(String(first[0]), ProgressRender.State.running.glyph)
        XCTAssertEqual(String(first[2..<5]), "1/2")
        XCTAssertEqual(String(first[9..<16]), "produce")
    }

    func testOverLongLabelIsTruncatedRatherThanPushingColumnsRight() {
        let long = ProgressRender.stepLine(
            state: .failed, index: 3, total: 4, label: String(repeating: "x", count: 60),
            engine: "shell", elapsed: "2s", outcome: "exit 1", palette: plain)
        let short = ProgressRender.stepLine(
            state: .failed, index: 3, total: 4, label: "short",
            engine: "shell", elapsed: "2s", outcome: "exit 1", palette: plain)
        XCTAssertTrue(long.contains("\u{2026}"))
        XCTAssertEqual(long.count, short.count)
    }

    func testQueuedLayerNamesWhatItIsWaitingFor() {
        let queued = ProgressRender.layerLine(
            state: .queued, label: "join", kind: "recipe", elapsed: "0s",
            deps: ["variants"], waitingOn: ["variants"], palette: plain)
        XCTAssertTrue(queued.hasSuffix("waiting on variants"))

        let running = ProgressRender.layerLine(
            state: .running, label: "variants", kind: "recipe", elapsed: "13s",
            deps: ["prep"], waitingOn: [], outcome: "running", palette: plain)
        XCTAssertTrue(running.hasSuffix("running"))

        let rootless = ProgressRender.layerLine(
            state: .ok, label: "prep", kind: "recipe", elapsed: "1m20s",
            deps: [], waitingOn: [], outcome: nil, palette: plain)
        XCTAssertTrue(rootless.hasSuffix("no deps"))

        let downstream = ProgressRender.layerLine(
            state: .ok, label: "join", kind: "recipe", elapsed: "2s",
            deps: ["variants"], waitingOn: [], outcome: nil, palette: plain)
        XCTAssertTrue(downstream.hasSuffix("after variants"))
    }

    func testLayerLinesShareTheStepLineColumns() {
        let layer = ProgressRender.layerLine(
            state: .ok, label: "prep", kind: "recipe", elapsed: "2s",
            deps: [], waitingOn: [], outcome: "ok", palette: plain)
        // Layer lines drop the counter column and keep everything else.
        XCTAssertEqual(layer.count, outcomeOffset - ProgressRender.Col.counter + 2)
    }

    func testDurationsReadTheSameWayTheSummaryLineWritesThem() {
        XCTAssertEqual(ProgressRender.duration(seconds: 3), "3s")
        XCTAssertEqual(ProgressRender.duration(seconds: 59), "59s")
        XCTAssertEqual(ProgressRender.duration(seconds: 252), "4m12s")
        XCTAssertEqual(ProgressRender.duration(seconds: 4020), "1h07m")
    }
}
