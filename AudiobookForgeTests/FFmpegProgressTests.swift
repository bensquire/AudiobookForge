import os
import XCTest
@testable import ForgeCore

/// Pins the progress plumbing between ffmpeg's stderr and the UI. ffmpeg
/// redraws its stats line in place, so every in-flight report ends in a
/// bare `\r` and only the last one in `\n`. These tests exist because the
/// buffer once split on `\n` alone and the bar sat at 0% for whole encodes.
final class FFmpegProgressTests: FFmpegTestCase {
    // MARK: - LineBuffer

    func test_lineBuffer_yieldsCarriageReturnTerminatedLines() {
        // Arrange — three in-flight reports the way ffmpeg writes them.
        let buffer = LineBuffer()
        let chunk = Data("size=1KiB time=00:00:01.00\rsize=2KiB time=00:00:02.00\rsize=3KiB time=00:00:03.00\r"
            .utf8)

        // Act
        let lines = buffer.append(chunk)

        // Assert — each report is its own line, in order, with nothing
        // held back for a `\n` that never comes.
        XCTAssertEqual(lines, [
            "size=1KiB time=00:00:01.00",
            "size=2KiB time=00:00:02.00",
            "size=3KiB time=00:00:03.00"
        ])
    }

    func test_lineBuffer_holdsPartialLineAcrossChunks() {
        // Arrange — a report split mid-token across two pipe reads.
        let buffer = LineBuffer()

        // Act
        let first = buffer.append(Data("size=1KiB time=00:0".utf8))
        let second = buffer.append(Data("0:01.00\rsize=2KiB time=00:00:02.00\n".utf8))

        // Assert
        XCTAssertEqual(first, [])
        XCTAssertEqual(second, ["size=1KiB time=00:00:01.00", "size=2KiB time=00:00:02.00"])
    }

    func test_lineBuffer_crlfDoesNotYieldEmptyLine() {
        // Arrange
        let buffer = LineBuffer()

        // Act
        let lines = buffer.append(Data("Output #0, mp4\r\nStream mapping:\n".utf8))

        // Assert — `\r\n` is one terminator, not a line plus a blank.
        XCTAssertEqual(lines, ["Output #0, mp4", "Stream mapping:"])
    }

    func test_lineBuffer_newlineOnlyStillWorks() {
        // Arrange
        let buffer = LineBuffer()

        // Act
        let lines = buffer.append(Data("a\nb\nc".utf8))

        // Assert — trailing partial line is retained until terminated.
        XCTAssertEqual(lines, ["a", "b"])
        XCTAssertEqual(buffer.append(Data("\n".utf8)), ["c"])
    }

    // MARK: - parseTime

    func test_parseTime_readsHoursMinutesSeconds() {
        XCTAssertEqual(
            FFmpegRunner.parseTime("size=  480KiB time=01:02:03.50 bitrate=65.5kbits/s"),
            3723.5
        )
    }

    func test_parseTime_nilWithoutTimeToken() {
        XCTAssertNil(FFmpegRunner.parseTime("Stream mapping:"))
        XCTAssertNil(FFmpegRunner.parseTime("time=N/A bitrate=N/A"))
    }

    // MARK: - end to end against the bundled ffmpeg

    /// A real encode must surface intermediate progress, not one callback
    /// at exit. `-stats_period` is forced low so the assertion doesn't
    /// depend on how fast this machine encodes a one-minute chapter.
    func test_run_reportsIntermediateProgressFromCarriageReturnLines() async throws {
        // Arrange
        let wav = tmp.appendingPathComponent("long.wav")
        let out = tmp.appendingPathComponent("long.m4a")
        let seconds = 60.0
        try writeSineWav(to: wav, seconds: seconds, frequency: 440, sampleRate: 8000)

        let args = ["-stats_period", "0.01"] + EncodeJob.phase1Args(
            input: wav, output: out, bitrate: "64k", sampleRate: 44100, channels: 1
        )
        let fractions = OSAllocatedUnfairLock<[Double]>(initialState: [])
        let secondsSeen = OSAllocatedUnfairLock<[Double]>(initialState: [])

        // Act
        try await FFmpegRunner.run(
            arguments: args,
            totalDuration: seconds,
            onProgress: { frac, secs in
                fractions.withLock { $0.append(frac) }
                secondsSeen.withLock { $0.append(secs) }
            }
        )

        // Assert — several reports arrived, monotonically, and at least
        // one landed strictly mid-encode rather than only at the end.
        let seen = fractions.withLock { $0 }
        XCTAssertGreaterThanOrEqual(seen.count, 3, "expected multiple progress reports, got \(seen)")
        XCTAssertEqual(seen, seen.sorted(), "progress went backwards: \(seen)")
        XCTAssertTrue(seen.contains { $0 > 0.05 && $0 < 0.95 }, "no intermediate progress: \(seen)")
        XCTAssertEqual(seen.last ?? 0, 1.0, accuracy: 0.02)
        // The seconds channel is the same reports in ffmpeg's own units.
        XCTAssertEqual(secondsSeen.withLock { $0 }.last ?? 0, seconds, accuracy: 1.5)
    }
}
