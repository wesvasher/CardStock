import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Lets SwiftUI code insert text at the editor's cursor.
@MainActor
final class MarkdownEditorController {
    fileprivate weak var textView: NSTextView?

    /// Where the cursor is (or the start of the selection).
    var cursorLocation: Int { textView?.selectedRange().location ?? 0 }

    /// Inserts Markdown for images as their own paragraphs at `location`
    /// (or the cursor), with blank lines around them. Undoable.
    func insertBlocks(_ blocks: [String], at location: Int? = nil) {
        guard let textView, !blocks.isEmpty else { return }
        let string = textView.string as NSString
        let selection = textView.selectedRange()
        let start = min(location ?? selection.location, string.length)
        let range = location == nil ? selection : NSRange(location: start, length: 0)

        func char(_ i: Int) -> unichar? { i >= 0 && i < string.length ? string.character(at: i) : nil }
        let newline: unichar = 10
        var before = ""
        if let c = char(start - 1), c != newline {
            before = "\n\n"
        } else if char(start - 1) == newline, let c = char(start - 2), c != newline {
            before = "\n"
        }
        let end = range.location + range.length
        var after = "\n\n"
        if char(end) == newline { after = char(end + 1) == newline ? "" : "\n" }
        if end >= string.length { after = "\n" }

        let text = before + blocks.joined(separator: "\n\n") + after
        guard textView.shouldChangeText(in: range, replacementString: text) else { return }
        textView.replaceCharacters(in: range, with: text)
        textView.didChangeText()
        let caret = range.location + (text as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.scrollRangeToVisible(NSRange(location: caret, length: 0))
        textView.window?.makeFirstResponder(textView)
    }

    // MARK: Formatting bar

    func bold() { wrap("**") }
    func italic() { wrap("*") }
    func strikethrough() { wrap("~~") }
    func code() { wrap("`") }
    func finePrint() { apply { MarkdownFormatting.toggleTag($0, $1, open: "<small>", close: "</small>") } }
    func link() { apply { MarkdownFormatting.link($0, $1) } }
    func heading(_ level: Int) { apply { MarkdownFormatting.heading($0, $1, level: level) } }
    func lines(_ style: MarkdownFormatting.LineStyle) { apply { MarkdownFormatting.toggleLines($0, $1, style: style) } }
    func divider() { insertBlocks(["---"]) }
    func sectionBreak() { insertBlocks([PageLayout.sectionBreak]) }
    func newsletter() { insertBlocks([PageWidget.newsletter.marker]) }
    func searchBox() { insertBlocks([PageWidget.search.marker]) }

    private func wrap(_ marker: String) {
        apply { MarkdownFormatting.toggleWrap($0, $1, marker: marker) }
    }

    /// Makes an edit through the text view so it can be undone.
    private func apply(_ make: (String, NSRange) -> MarkdownFormatting.Edit) {
        guard let textView else { return }
        let edit = make(textView.string, textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selection)
        textView.scrollRangeToVisible(edit.selection)
    }

    /// ⌘B, ⌘I and ⌘K while typing. Returns false for other keys.
    fileprivate func handleShortcut(_ key: String) -> Bool {
        switch key {
        case "b": bold()
        case "i": italic()
        case "k": link()
        default: return false
        }
        return true
    }
}

/// A plain-text Markdown editor (NSTextView) that accepts dropped and
/// pasted images and reports where they should go.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    let controller: MarkdownEditorController
    /// Image files to insert, and the character position to insert them at.
    let onImages: ([URL], Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = ImageDropTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? ImageDropTextView else { return scrollView }
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.onImages = { urls, index in context.coordinator.parent.onImages(urls, index) }
        textView.onShortcut = { [weak controller] key in controller?.handleShortcut(key) ?? false }
        textView.typingAttributes = MarkdownStyler.baseAttributes
        textView.string = text
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 10)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.registerForDraggedTypes(ImageDropTextView.imageDragTypes)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        controller.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        controller.textView = textView
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        var parent: MarkdownEditor
        init(_ parent: MarkdownEditor) { self.parent = parent }

        /// Restyles after each change to the text.
        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            // Text storage edits happen on the main thread.
            nonisolated(unsafe) let storage = textStorage
            MainActor.assumeIsolated { MarkdownStyler.style(storage) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// NSTextView that turns dropped or pasted images into an `onImages` call
/// instead of inserting file paths. Supports Finder files, Photos (file
/// promises) and raw image data.
final class ImageDropTextView: NSTextView {
    var onImages: (([URL], Int) -> Void)?
    /// Formatting shortcuts (⌘B, ⌘I, ⌘K). Returns true when handled.
    var onShortcut: ((String) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let key = event.charactersIgnoringModifiers?.lowercased(),
           onShortcut?(key) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Keep typing in the plain style; the styler applies formatting.
    override func didChangeText() {
        super.didChangeText()
        typingAttributes = MarkdownStyler.baseAttributes
    }

    static let imageDragTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .png, .tiff] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    override class func scrollableTextView() -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = ImageDropTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    private func hasImages(_ pasteboard: NSPasteboard) -> Bool {
        if !imageFileURLs(pasteboard).isEmpty { return true }
        if pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil) { return true }
        return pasteboard.availableType(from: [.png, .tiff]) != nil
            && pasteboard.availableType(from: [.string]) == nil
    }

    private func imageFileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter(ImageImporter.isImage)
    }

    private func dropIndex(_ sender: NSDraggingInfo) -> Int {
        let point = convert(sender.draggingLocation, from: nil)
        return characterIndexForInsertion(at: point)
    }

    // MARK: Dragging

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasImages(sender.draggingPasteboard) ? draggingUpdated(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard hasImages(sender.draggingPasteboard) else { return super.draggingUpdated(sender) }
        // Show where the images will land.
        setSelectedRange(NSRange(location: dropIndex(sender), length: 0))
        window?.makeFirstResponder(self)
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard hasImages(pasteboard) else { return super.performDragOperation(sender) }
        let index = dropIndex(sender)
        receiveImages(from: pasteboard, at: index)
        return true
    }

    // MARK: Pasting

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general
        guard hasImages(pasteboard) else { return super.paste(sender) }
        receiveImages(from: pasteboard, at: selectedRange().location)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        super.readablePasteboardTypes + [.png, .tiff]
    }

    // MARK: Receiving

    private func receiveImages(from pasteboard: NSPasteboard, at index: Int) {
        let files = imageFileURLs(pasteboard)
        if !files.isEmpty {
            onImages?(files, index)
            return
        }
        let inbox = FileManager.default.temporaryDirectory.appending(path: "CardStock-Incoming-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        // Photos and some other apps hand over "promised" files.
        if let promises = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            let group = DispatchGroup()
            let received = ReceivedURLs()
            for promise in promises {
                group.enter()
                promise.receivePromisedFiles(atDestination: inbox, options: [:], operationQueue: .main) { url, error in
                    if error == nil, ImageImporter.isImage(url) { received.append(url) }
                    group.leave()
                }
            }
            group.notify(queue: .main) { [weak self] in
                let urls = received.all
                if !urls.isEmpty { self?.onImages?(urls, index) }
            }
            return
        }

        // Raw image data, e.g. a screenshot copied to the clipboard.
        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff).flatMap(Self.pngData) {
            let url = inbox.appending(path: "Pasted Image.png")
            if (try? data.write(to: url)) != nil { onImages?([url], index) }
        }
    }

    private static func pngData(fromTIFF tiff: Data) -> Data? {
        NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    }
}

private final class ReceivedURLs: @unchecked Sendable {
    private var urls: [URL] = []
    private let lock = NSLock()
    func append(_ url: URL) { lock.withLock { urls.append(url) } }
    var all: [URL] { lock.withLock { urls } }
}
