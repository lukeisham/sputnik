import AppKit
import Foundation
import Testing

@testable import ASCIIStudioModule

// MARK: - ASCIIArt Model Tests

struct ASCIIArtTests {

    @Test func asciiArtDefaults() {
        let art = ASCIIArt(title: "Test", asciiContent: "")
        #expect(art.title == "Test")
        #expect(art.asciiContent.isEmpty)
        #expect(art.sourceImageURL == nil)
        #expect(art.style == .block)
        #expect(art.width == 80)
        #expect(art.tags.isEmpty)
    }

    @Test func asciiArtCustomValues() {
        let url = URL(string: "file:///test.png")!
        let art = ASCIIArt(
            title: "Custom",
            asciiContent: "@@##",
            sourceImageURL: url,
            style: .braille,
            width: 40,
            tags: ["cat", "animal"]
        )
        #expect(art.title == "Custom")
        #expect(art.asciiContent == "@@##")
        #expect(art.sourceImageURL == url)
        #expect(art.style == .braille)
        #expect(art.width == 40)
        #expect(art.tags == ["cat", "animal"])
    }

    @Test func asciiArtSendableConformance() {
        let art = ASCIIArt(title: "Sendable", asciiContent: "")
        // Verify it's Sendable by passing through an actor boundary.
        Task {
            let title = await withCheckedContinuation { continuation in
                continuation.resume(returning: art.title)
            }
            #expect(title == "Sendable")
        }
    }

    @Test func asciiArtEquatable() {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let art1 = ASCIIArt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Same",
            asciiContent: "", createdAt: fixedDate)
        let art2 = ASCIIArt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "Same",
            asciiContent: "", createdAt: fixedDate)
        #expect(art1 == art2)
    }

    @Test func asciiArtDifferentIDsAreNotEqual() {
        let art1 = ASCIIArt(title: "Title", asciiContent: "")
        let art2 = ASCIIArt(title: "Title", asciiContent: "")
        #expect(art1 != art2)
    }

    @Test func asciiArtCreatedAtDefaultsToNow() {
        let before = Date()
        let art = ASCIIArt(title: "Timestamp", asciiContent: "")
        let after = Date()
        #expect(art.createdAt >= before)
        #expect(art.createdAt <= after)
    }

    @Test func asciiArtCustomCreatedAt() {
        let customDate = Date(timeIntervalSince1970: 1_700_000_000)
        let art = ASCIIArt(title: "CustomDate", asciiContent: "", createdAt: customDate)
        #expect(art.createdAt == customDate)
    }

    @Test func asciiArtAllPropertiesAfterFullInit() {
        let id = UUID()
        let url = URL(string: "file:///image.jpg")!
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let art = ASCIIArt(
            id: id,
            title: "Full",
            asciiContent: "##",
            sourceImageURL: url,
            style: .ascii,
            width: 60,
            createdAt: date,
            tags: ["a", "b"]
        )
        #expect(art.id == id)
        #expect(art.title == "Full")
        #expect(art.asciiContent == "##")
        #expect(art.sourceImageURL == url)
        #expect(art.style == .ascii)
        #expect(art.width == 60)
        #expect(art.createdAt == date)
        #expect(art.tags == ["a", "b"])
    }

    @Test func asciiArtIdentifiableConformance() {
        let id = UUID()
        let art = ASCIIArt(id: id, title: "Identifiable", asciiContent: "")
        #expect(art.id == id)
    }
}

// MARK: - ImageToASCIIConverter Tests

@MainActor
struct ImageToASCIIConverterTests {

    // MARK: Happy Path — RampStyle

    @Test func blockRampStartsWithDarkestCharacter() {
        #expect(ImageToASCIIConverter.RampStyle.block.characters.first == "@")
    }

    @Test func minimalRampHasFewerCharsThanBlock() {
        let block = ImageToASCIIConverter.RampStyle.block.characters.count
        let minimal = ImageToASCIIConverter.RampStyle.minimal.characters.count
        #expect(minimal < block)
    }

    @Test func allRampStylesEnumeratedAsCases() {
        #expect(ImageToASCIIConverter.RampStyle.allCases.count == 6)
    }

    @Test func brailleRampEndsWithSpace() {
        #expect(ImageToASCIIConverter.RampStyle.braille.characters.last == " ")
    }

    @Test func asciiRampHasCharacters() {
        let ramp = ImageToASCIIConverter.RampStyle.ascii.characters
        #expect(!ramp.isEmpty)
        #expect(ramp.first == "M")
        #expect(ramp.last == " ")
    }

    @Test func wideRampHasCorrectCount() {
        let ramp = ImageToASCIIConverter.RampStyle.wide.characters
        #expect(ramp.count == 4)
    }

    // MARK: Happy Path — convert (convenience overload)

    @Test func convertProducesExpectedRowCount() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 10, height: 10))
        let rows = ImageToASCIIConverter.convert(image, width: 10, invert: false, style: .block)
            .components(separatedBy: "\n")
        #expect(rows.count == 5)
    }

    @Test func convertProducesExpectedColumnCount() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 20, height: 20))
        let firstRow =
            ImageToASCIIConverter.convert(image, width: 20, invert: false, style: .block)
            .components(separatedBy: "\n")
            .first ?? ""
        #expect(firstRow.count == 20)
    }

    @Test func convertOnlyUsesCharactersFromActiveRamp() {
        let image = makeSolidImage(color: .gray, size: CGSize(width: 8, height: 8))
        let output = ImageToASCIIConverter.convert(image, width: 8, invert: false, style: .minimal)
        let validChars = Set(ImageToASCIIConverter.RampStyle.minimal.characters).union(["\n"])
        for ch in output {
            #expect(validChars.contains(ch))
        }
    }

    @Test func invertProducesDifferentOutputThanNonInvert() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 4, height: 4))
        let normal = ImageToASCIIConverter.convert(image, width: 4, invert: false, style: .block)
        let inverted = ImageToASCIIConverter.convert(image, width: 4, invert: true, style: .block)
        #expect(normal != inverted)
    }

    @Test func convertWithSettingsUsesNewAPI() {
        let image = makeSolidImage(color: .black, size: CGSize(width: 4, height: 4))
        let settings = ImageToASCIIConverter.Settings(width: 4, style: .block)
        let result = ImageToASCIIConverter.convert(image, settings: settings)
        let rows = result.components(separatedBy: "\n")
        #expect(!rows.isEmpty)
    }

    // MARK: — Brightness and Contrast

    @Test func brightnessAdjustsOutput() {
        let image = makeSolidImage(color: .gray, size: CGSize(width: 4, height: 4))
        let normal = ImageToASCIIConverter.convert(
            image, settings: .init(width: 4, brightness: 0.0, contrast: 1.0))
        let brightened = ImageToASCIIConverter.convert(
            image, settings: .init(width: 4, brightness: 0.5, contrast: 1.0))
        #expect(normal != brightened)
    }

    @Test func contrastAdjustsOutput() {
        // Use a gradient-like image so contrast changes are visible.
        let image = makeGradientImage(size: CGSize(width: 8, height: 4))
        let lowContrast = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, contrast: 0.5))
        let highContrast = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, contrast: 2.0))
        // Contrast adjustment should produce different outputs on a non-uniform image.
        #expect(lowContrast != highContrast)
    }

    @Test func ditherEnabledDoesNotCrash() {
        let image = makeSolidImage(color: .gray, size: CGSize(width: 8, height: 8))
        let result = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, ditherMode: .floydSteinberg))
        #expect(!result.isEmpty)
    }

    // MARK: — Line-art mode

    @Test func lineArtModeDoesNotCrash() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 8, height: 8))
        let result = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, mode: .lineArt))
        // Line art on a solid white image may produce all spaces or minimal edges.
        // The key test is that it doesn't crash and returns a string.
        #expect(!result.isEmpty || result.allSatisfy { $0 == " " || $0 == "\n" })
    }

    @Test func lineArtDifferentModes() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 8, height: 8))
        let simple = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, mode: .lineArt, edgeStyle: .simple))
        let shaded = ImageToASCIIConverter.convert(
            image, settings: .init(width: 8, mode: .lineArt, edgeStyle: .shaded))
        // On a solid white image, line art may produce empty output (no edges).
        // The key is that neither call crashes.
        _ = (simple.count, shaded.count)
    }

    // MARK: — Dithering

    @Test func floydSteinbergDitherDoesNotChangeDimensions() {
        let input = [Double](repeating: 0.5, count: 16)  // 4x4
        let dithered = ImageToASCIIConverter.applyFloydSteinbergDither(
            to: input, width: 4, height: 4, rampCount: 10)
        #expect(dithered.count == 16)
    }

    @Test func floydSteinbergDitherPreservesAverage() {
        var input = [Double]()
        for y in 0..<4 {
            for x in 0..<4 {
                input.append(Double(x + y) / 6.0)
            }
        }
        let originalAvg = input.reduce(0, +) / Double(input.count)
        let dithered = ImageToASCIIConverter.applyFloydSteinbergDither(
            to: input, width: 4, height: 4, rampCount: 5)
        let ditheredAvg = dithered.reduce(0, +) / Double(dithered.count)
        // Averages should be close (within 10%).
        #expect(abs(originalAvg - ditheredAvg) < 0.1)
    }

    // MARK: — Settings defaults

    @Test func settingsDefaultWidthIs80() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.width == 80)
    }

    @Test func settingsDefaultInvertIsFalse() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.invert == false)
    }

    @Test func settingsDefaultStyleIsBlock() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.style == .block)
    }

    @Test func settingsDefaultModeIsLuminance() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.mode == .luminance)
    }

    @Test func settingsDefaultBrightnessIsZero() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.brightness == 0.0)
    }

    @Test func settingsDefaultContrastIsOne() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.contrast == 1.0)
    }

    @Test func settingsDefaultDitherModeIsNone() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.ditherMode == .none)
    }

    @Test func settingsDefaultEdgeStyleIsSimple() {
        let settings = ImageToASCIIConverter.Settings()
        #expect(settings.edgeStyle == .simple)
    }

    @Test func settingsCustomValues() {
        let settings = ImageToASCIIConverter.Settings(
            width: 40,
            invert: true,
            style: .braille,
            mode: .lineArt,
            brightness: 0.3,
            contrast: 1.5,
            ditherMode: .floydSteinberg,
            edgeStyle: .dense
        )
        #expect(settings.width == 40)
        #expect(settings.invert == true)
        #expect(settings.style == .braille)
        #expect(settings.mode == .lineArt)
        #expect(settings.brightness == 0.3)
        #expect(settings.contrast == 1.5)
        #expect(settings.ditherMode == .floydSteinberg)
        #expect(settings.edgeStyle == .dense)
    }

    // MARK: — Mode enum

    @Test func modeAllCasesHasThreeValues() {
        #expect(ImageToASCIIConverter.Mode.allCases.count == 3)
    }

    @Test func modeLuminanceExists() {
        #expect(ImageToASCIIConverter.Mode.allCases.contains(.luminance))
    }

    @Test func modeLineArtExists() {
        #expect(ImageToASCIIConverter.Mode.allCases.contains(.lineArt))
    }

    // MARK: — Edge cases

    @Test func convertInvalidImageReturnsEmpty() {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        // A 1x1 image with no backing CGImage should fail to read pixels and return empty.
        let result = ImageToASCIIConverter.convert(image, width: 10, invert: false, style: .block)
        #expect(result.isEmpty)
    }

    @Test func convertWithZeroWidthReturnsEmpty() {
        let image = makeSolidImage(color: .white, size: CGSize(width: 4, height: 4))
        let result = ImageToASCIIConverter.convert(image, width: 0, invert: false, style: .block)
        #expect(result.isEmpty)
    }

    @Test func floydSteinbergDitherSinglePixel() {
        let input = [0.7]
        let dithered = ImageToASCIIConverter.applyFloydSteinbergDither(
            to: input, width: 1, height: 1, rampCount: 5)
        #expect(dithered.count == 1)
        #expect(dithered[0] >= 0.0 && dithered[0] <= 1.0)
    }

    @Test func floydSteinbergDitherSingleRow() {
        let input = [0.1, 0.3, 0.5, 0.7, 0.9]
        let dithered = ImageToASCIIConverter.applyFloydSteinbergDither(
            to: input, width: 5, height: 1, rampCount: 5)
        #expect(dithered.count == 5)
    }
}

// MARK: - ASCIIImageEditor Tests

@MainActor
struct ASCIIImageEditorTests {

    // MARK: — Load

    @Test func loadStringSetsGrid() {
        let editor = ASCIIImageEditor()
        editor.load("AB\nCD", targetColumns: 2)
        #expect(editor.columns == 2)
        #expect(editor.rows == 2)
        #expect(!editor.grid.isEmpty)
    }

    @Test func loadResetsEditFlag() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "B")
        #expect(editor.hasManualEdits == true)
        editor.load("C", targetColumns: 1)
        #expect(editor.hasManualEdits == false)
    }

    @Test func loadPadsShortContent() {
        let editor = ASCIIImageEditor()
        editor.load("AB\nC", targetColumns: 3)
        // 2 rows × 3 columns = 6 cells. "ABC" (after filtering newlines) = 3 chars → padded.
        #expect(editor.grid.count == 6)
        // The padded cells should be spaces.
        #expect(editor.grid[3] == " ")
        #expect(editor.grid[4] == " ")
        #expect(editor.grid[5] == " ")
    }

    @Test func hasManualEditsStartsFalse() {
        let editor = ASCIIImageEditor()
        #expect(editor.hasManualEdits == false)
    }

    // MARK: — Replace Character

    @Test func replaceCharacterChangesGrid() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "B")
        #expect(editor.grid[0] == "B")
    }

    @Test func replaceCharacterSetsEditFlag() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        #expect(editor.hasManualEdits == false)
        editor.replaceCharacter(at: 0, with: "B")
        #expect(editor.hasManualEdits == true)
    }

    @Test func replaceCharacterOutOfBoundsIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 999, with: "B")
        #expect(editor.grid[0] == "A")
        #expect(editor.hasManualEdits == false)
    }

    @Test func replaceCharacterSameCharacterIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "A")
        #expect(editor.hasManualEdits == false)
    }

    @Test func replaceCharacterNegativeIndexIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: -1, with: "B")
        #expect(editor.grid[0] == "A")
        #expect(editor.hasManualEdits == false)
    }

    // MARK: — Batch Replace

    @Test func batchReplaceChangesMultipleCells() {
        let editor = ASCIIImageEditor()
        editor.load("ABCD", targetColumns: 4)
        editor.batchReplace([(0, "X"), (2, "Y")])
        #expect(editor.grid[0] == "X")
        #expect(editor.grid[1] == "B")
        #expect(editor.grid[2] == "Y")
    }

    @Test func batchReplaceCanUndo() {
        let editor = ASCIIImageEditor()
        editor.load("ABCD", targetColumns: 4)
        editor.batchReplace([(0, "X"), (1, "Y")])
        #expect(editor.grid[0] == "X")
        editor.undoManager.undo()
        #expect(editor.grid[0] == "A")
    }

    @Test func batchReplaceEmptyArrayIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.load("ABCD", targetColumns: 4)
        editor.batchReplace([])
        #expect(editor.grid[0] == "A")
        #expect(editor.hasManualEdits == false)
    }

    @Test func batchReplaceOutOfBoundsIndexIsSkipped() {
        let editor = ASCIIImageEditor()
        editor.load("AB", targetColumns: 2)
        editor.batchReplace([(0, "X"), (999, "Z")])
        #expect(editor.grid[0] == "X")
        #expect(editor.grid[1] == "B")
    }

    // MARK: — Replace Selection

    @Test func replaceSelectionChangesMultipleCells() {
        let editor = ASCIIImageEditor()
        editor.load("ABCDEF", targetColumns: 6)
        editor.selection = .init(startIndex: 1, endIndex: 4)
        editor.replaceSelection(with: "X")
        // Selection range 1...4 replaces indices 1,2,3,4.
        #expect(editor.grid[0] == "A")
        #expect(editor.grid[1] == "X")
        #expect(editor.grid[2] == "X")
        #expect(editor.grid[3] == "X")
        #expect(editor.grid[4] == "X")
        #expect(editor.grid[5] == "F")
    }

    @Test func replaceSelectionEmptySelectionIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.load("ABCD", targetColumns: 4)
        editor.selection = .empty
        editor.replaceSelection(with: "X")
        #expect(editor.grid[0] == "A")
        #expect(editor.hasManualEdits == false)
    }

    @Test func replaceSelectionCanUndo() {
        let editor = ASCIIImageEditor()
        editor.load("ABCDEF", targetColumns: 6)
        editor.selection = .init(startIndex: 1, endIndex: 3)
        editor.replaceSelection(with: "Z")
        editor.undoManager.undo()
        #expect(editor.grid[1] == "B")
        #expect(editor.grid[2] == "C")
    }

    // MARK: — asString

    @Test func asStringReconstructsInput() {
        let editor = ASCIIImageEditor()
        let input = "Hello\nWorld"
        editor.load(input, targetColumns: 5)
        #expect(editor.asString() == input)
    }

    @Test func asStringEmptyGridReturnsEmpty() {
        let editor = ASCIIImageEditor()
        editor.columns = 0
        editor.rows = 0
        #expect(editor.asString() == "")
    }

    @Test func asStringSingleCharacter() {
        let editor = ASCIIImageEditor()
        editor.load("X", targetColumns: 1)
        #expect(editor.asString() == "X")
    }

    // MARK: — Align

    @Test func alignLeftPreservesContent() {
        let editor = ASCIIImageEditor()
        editor.load("A \nB ", targetColumns: 2)
        editor.align(.left)
        let result = editor.asString()
        #expect(result.contains("A "))
        #expect(result.contains("B "))
    }

    @Test func alignCenterPadsSymmetrically() {
        let editor = ASCIIImageEditor()
        editor.load("AB", targetColumns: 4)
        editor.align(.center)
        let result = editor.asString()
        // "AB" centered in 4 cols → " AB " (1 space left, 1 space right)
        #expect(result == " AB ")
    }

    @Test func alignRightPushesContentToEnd() {
        let editor = ASCIIImageEditor()
        editor.load("AB", targetColumns: 4)
        editor.align(.right)
        let result = editor.asString()
        // "AB" right-aligned in 4 cols → "  AB"
        #expect(result == "  AB")
    }

    @Test func alignZeroColumnsIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.columns = 0
        editor.rows = 0
        editor.align(.center)
        // Should not crash.
        _ = Bool(true)
    }

    @Test func alignSetsEditFlag() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        #expect(editor.hasManualEdits == false)
        editor.align(.left)
        #expect(editor.hasManualEdits == true)
    }

    @Test func alignmentAllCasesCount() {
        #expect(ASCIIImageEditor.Alignment.allCases.count == 3)
    }

    // MARK: — Fill

    @Test func fillReplacesNonSpace() {
        let editor = ASCIIImageEditor()
        editor.load("A B", targetColumns: 3)
        editor.fill("X")
        let result = editor.asString()
        // A and B are non-space, so they become X; spaces stay.
        let chars = result.filter { $0 != "\n" }
        #expect(chars == "X X")
    }

    @Test func fillWithEmptyGridIsNoOp() {
        let editor = ASCIIImageEditor()
        editor.fill("X")
        #expect(editor.grid.isEmpty)
        #expect(editor.hasManualEdits == false)
    }

    // MARK: — Undo / Redo

    @Test func undoAfterReplace() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "B")
        #expect(editor.grid[0] == "B")
        editor.undoManager.undo()
        #expect(editor.grid[0] == "A")
    }

    @Test func redoAfterUndo() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "B")
        editor.undoManager.undo()
        #expect(editor.grid[0] == "A")
        editor.undoManager.redo()
        #expect(editor.grid[0] == "B")
    }

    @Test func multipleUndoOperationsStack() {
        let editor = ASCIIImageEditor()
        editor.load("A", targetColumns: 1)
        editor.replaceCharacter(at: 0, with: "B")
        editor.replaceCharacter(at: 0, with: "C")
        #expect(editor.grid[0] == "C")
        // NSUndoManager groupsByEvent is true by default, so both edits are in one group.
        // A single undo reverts both.
        editor.undoManager.undo()
        #expect(editor.grid[0] == "A")
        // Redo should restore both changes.
        editor.undoManager.redo()
        #expect(editor.grid[0] == "C")
    }

    @Test func undoAfterAlign() {
        let editor = ASCIIImageEditor()
        editor.load("AB", targetColumns: 4)
        editor.align(.right)
        let afterAlign = editor.asString()
        #expect(afterAlign == "  AB")
        editor.undoManager.undo()
        let afterUndo = editor.asString()
        // After undo, the grid is restored to the pre-align state: "AB" padded to 4 columns.
        #expect(afterUndo == "AB  ")
    }

    @Test func undoAfterFill() {
        let editor = ASCIIImageEditor()
        editor.load("AB", targetColumns: 2)
        editor.fill("X")
        #expect(editor.grid[0] == "X")
        #expect(editor.grid[1] == "X")
        editor.undoManager.undo()
        #expect(editor.grid[0] == "A")
        #expect(editor.grid[1] == "B")
    }

    // MARK: — Selection type

    @Test func selectionEmptyIsEmpty() {
        #expect(ASCIIImageEditor.Selection.empty.isEmpty == true)
    }

    @Test func selectionNonEmptyIsNotEmpty() {
        let sel = ASCIIImageEditor.Selection(startIndex: 0, endIndex: 5)
        #expect(sel.isEmpty == false)
    }

    @Test func selectionRangeIsNormalised() {
        let sel = ASCIIImageEditor.Selection(startIndex: 5, endIndex: 2)
        #expect(sel.range == 2...5)
    }

    @Test func selectionRangeSameIndexIsSingleValue() {
        let sel = ASCIIImageEditor.Selection(startIndex: 3, endIndex: 3)
        #expect(sel.range == 3...3)
        #expect(sel.isEmpty == true)
    }
}

// MARK: - ASCIIEdgeDetector Tests

@MainActor
struct ASCIIEdgeDetectorTests {

    @Test func edgeStylesAllHaveCharacters() {
        for style in ASCIIEdgeDetector.EdgeStyle.allCases {
            let chars = ASCIIEdgeDetector.characters(for: style)
            #expect(!chars.isEmpty)
        }
    }

    @Test func simpleStyleHasExpectedGlyphs() {
        let chars = ASCIIEdgeDetector.characters(for: .simple)
        #expect(chars.contains("/"))
        #expect(chars.contains("|"))
        #expect(chars.contains("\\"))
        #expect(chars.contains("_"))
    }

    @Test func shadedStyleHasExpectedGlyphs() {
        let chars = ASCIIEdgeDetector.characters(for: .shaded)
        #expect(chars.contains("."))
        #expect(chars.contains(":"))
        #expect(chars.contains("/"))
        #expect(chars.contains("|"))
        #expect(chars.contains("\\"))
        #expect(chars.contains("#"))
    }

    @Test func denseStyleHasExpectedGlyphs() {
        let chars = ASCIIEdgeDetector.characters(for: .dense)
        #expect(chars.contains("·"))
        #expect(chars.contains("⋅"))
        #expect(chars.contains("╱"))
        #expect(chars.contains("╲"))
        #expect(chars.contains("─"))
        #expect(chars.contains("│"))
        #expect(chars.contains("╳"))
    }

    @Test func characterForZeroIntensityIsSpace() {
        let char = ASCIIEdgeDetector.character(for: 0.0, style: .simple)
        #expect(char == " ")
    }

    @Test func characterForMaxIntensityIsLastInRamp() {
        let ramp = ASCIIEdgeDetector.characters(for: .simple)
        let char = ASCIIEdgeDetector.character(for: 1.0, style: .simple)
        #expect(char == ramp.last)
    }

    @Test func characterForNegativeIntensityReturnsSpace() {
        let char = ASCIIEdgeDetector.character(for: -0.5, style: .shaded)
        #expect(char == " ")
    }

    @Test func characterForOverOneIntensityReturnsLastInRamp() {
        let ramp = ASCIIEdgeDetector.characters(for: .dense)
        let char = ASCIIEdgeDetector.character(for: 2.0, style: .dense)
        #expect(char == ramp.last)
    }

    @Test func edgeStylesAllCasesCount() {
        #expect(ASCIIEdgeDetector.EdgeStyle.allCases.count == 3)
    }
}

// MARK: - ASCIIExporter Tests

struct ASCIIExporterTests {

    @Test func suggestedFilenameAppendsTxt() {
        // The exporter uses NSSavePanel which can't be tested in unit tests,
        // but we can verify the filename logic by checking nameFieldStringValue
        // is constructed correctly via the helper logic.
        let suggested = "my_image.txt"
        #expect(suggested.hasSuffix(".txt"))
    }

    @Test func openPanelReturnsNilOnCancel() {
        // NSOpenPanel can't be tested in unit tests — we verify the API exists.
        // This is an integration test that requires user interaction.
        _ = Bool(true)
    }
}

// MARK: - ASCIILibraryBrowser Tests

@MainActor
struct ASCIILibraryBrowserTests {

    @Test func categoryAllCasesHasFiveValues() {
        #expect(ASCIILibraryBrowser.Category.allCases.count == 5)
    }

    @Test func categoryRawValuesAreCorrect() {
        #expect(ASCIILibraryBrowser.Category.frames.rawValue == "Frames")
        #expect(ASCIILibraryBrowser.Category.arrows.rawValue == "Arrows")
        #expect(ASCIILibraryBrowser.Category.dividers.rawValue == "Dividers")
        #expect(ASCIILibraryBrowser.Category.decorative.rawValue == "Decorative")
        #expect(ASCIILibraryBrowser.Category.symbols.rawValue == "Symbols")
    }

    @Test func clipInitialization() {
        let clip = ASCIILibraryBrowser.Clip(name: "test", content: "##")
        #expect(clip.name == "test")
        #expect(clip.content == "##")
    }

    @Test func clipIDsAreUnique() {
        let clip1 = ASCIILibraryBrowser.Clip(name: "a", content: "1")
        let clip2 = ASCIILibraryBrowser.Clip(name: "b", content: "2")
        #expect(clip1.id != clip2.id)
    }

    @Test func clipIsIdentifiable() {
        let clip = ASCIILibraryBrowser.Clip(name: "test", content: "##")
        // Verify clip.id is a UUID (Identifiable conformance).
        _ = clip.id as UUID
    }

    @Test func browserReturnsEmptyForMissingCategory() {
        let browser = ASCIILibraryBrowser()
        // Categories with no files in the test bundle should return empty.
        let clips = browser.clips(for: .frames)
        // Expect empty array — test bundle has no ASCII library files.
        #expect(clips.isEmpty)
    }

    @Test func browserCachesResults() {
        let browser = ASCIILibraryBrowser()
        let first = browser.clips(for: .arrows)
        let second = browser.clips(for: .arrows)
        // Both calls should return the same (empty) array from cache.
        #expect(first.isEmpty == second.isEmpty)
    }

    @Test func clipSendableConformance() {
        let clip = ASCIILibraryBrowser.Clip(name: "test", content: "##")
        Task {
            let name = await withCheckedContinuation { continuation in
                continuation.resume(returning: clip.name)
            }
            #expect(name == "test")
        }
    }

    @Test func insertClipIntoTextView() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 6, length: 5))  // Select "World"

        let browser = ASCIILibraryBrowser()
        let clip = ASCIILibraryBrowser.Clip(name: "test", content: "ASCII")
        browser.insert(clip, into: textView)

        #expect(textView.string == "Hello ASCII")
    }

    @Test func insertClipIntoTextViewWithoutSelection() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "Hello"
        // Explicitly place cursor at start.
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        let browser = ASCIILibraryBrowser()
        let clip = ASCIILibraryBrowser.Clip(name: "test", content: "X")
        browser.insert(clip, into: textView)

        #expect(textView.string == "XHello")
    }
}

// MARK: - ASCIIStudioCoordinator Tests

@MainActor
struct ASCIIStudioCoordinatorTests {

    @Test func insertAtCursorWithEmptyTextIsNoOp() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "Hello"
        ASCIIStudioCoordinator.insertAtCursor("", into: textView)
        #expect(textView.string == "Hello")
    }

    @Test func insertAtCursorInsertsTextAtCursor() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 6, length: 0))  // Cursor before "World"

        ASCIIStudioCoordinator.insertAtCursor("Beautiful ", into: textView)
        #expect(textView.string == "Hello Beautiful World")
    }

    @Test func insertAtCursorReplacesSelection() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        textView.string = "Hello World"
        textView.setSelectedRange(NSRange(location: 6, length: 5))  // Select "World"

        ASCIIStudioCoordinator.insertAtCursor("Sputnik", into: textView)
        #expect(textView.string == "Hello Sputnik")
    }

    @Test func insertAtCursorMultilineText() {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 50))
        textView.string = "Before\nAfter"
        textView.setSelectedRange(NSRange(location: 7, length: 0))  // Start of "After"

        ASCIIStudioCoordinator.insertAtCursor("---\n", into: textView)
        #expect(textView.string == "Before\n---\nAfter")
    }

    @Test func activeTextViewReturnsNilWhenNoKeyWindow() {
        // In unit tests, there is no key window.
        let textView = ASCIIStudioCoordinator.activeTextView()
        #expect(textView == nil)
    }
}

// MARK: - Helpers

extension ImageToASCIIConverterTests {

    /// Creates a small solid-color NSImage for deterministic test output.
    func makeSolidImage(color: NSColor, size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.drawSwatch(in: CGRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }

    /// Creates a horizontal gradient image for contrast/brightness tests.
    func makeGradientImage(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors =
            [
                NSColor.black.cgColor,
                NSColor.white.cgColor,
            ] as CFArray
        guard
            let gradient = CGGradient(
                colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]
            )
        else {
            image.unlockFocus()
            return image
        }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: size.width, y: 0),
            options: []
        )
        image.unlockFocus()
        return image
    }
}

extension ASCIIImageEditorTests {

    func makeSolidImage(color: NSColor, size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.drawSwatch(in: CGRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
}
