#if os(macOS)
/**
 *  MacEditorTextView
 *  Copyright (c) Thiago Holanda 2020
 *  https://twitter.com/tholanda
 *
 *  Modified by Kyle Nazario 2020
 *
 *  MIT license
 */

import AppKit
import SwiftUI

public struct HighlightedTextEditor: NSViewRepresentable, @MainActor HighlightingTextEditor {
    let font: NSFont
    
    public struct Internals {
        public let textView: SystemTextView
        public let scrollView: SystemScrollView?
    }

    @Binding var text: String {
        didSet {
            onTextChange?(text)
        }
    }

    let highlightRules: [HighlightRule]

    private(set) var onEditingChanged: OnEditingChangedCallback?
    private(set) var onCommit: OnCommitCallback?
    private(set) var onTextChange: OnTextChangeCallback?
    private(set) var onSelectionChange: OnSelectionChangeCallback?
    private(set) var introspect: IntrospectCallback?

    public init(
        text: Binding<String>,
        highlightRules: [HighlightRule],
        font: NSFont = defaultEditorFont
    ) {
        _text = text
        self.highlightRules = highlightRules
        self.font = font
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> ScrollableTextView {
        let view = ScrollableTextView(highlightRules: highlightRules, font: font)
        view.delegate = context.coordinator
        view.textView.string = text
        runIntrospect(view)
        return view
    }

    public func updateNSView(_ view: ScrollableTextView, context: Context) {
        context.coordinator.updatingNSView = true
        defer { context.coordinator.updatingNSView = false }
        
        if view.textView.string != text {
            view.setText(text)
        }
        
        var attributes = view.textView.typingAttributes
        if attributes[.font] == nil {
            attributes[.font] = font
        }
        if attributes[.foregroundColor] == nil {
            attributes[.foregroundColor] = NSColor.textColor
        }
        view.textView.typingAttributes = attributes
    }

    private func runIntrospect(_ view: ScrollableTextView) {
        guard let introspect = introspect else { return }
        let internals = Internals(textView: view.textView, scrollView: view.scrollView)
        introspect(internals)
    }
}

public extension HighlightedTextEditor {
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightedTextEditor
        var selectedRanges: [NSValue] = []
        var updatingNSView = false
        var isProgrammaticChange = false
        
        var lastPlainText: String = ""
        var lastHighlightedText: NSAttributedString = NSAttributedString()

        init(_ parent: HighlightedTextEditor) {
            self.parent = parent
        }

        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            return true
        }

        public func textDidBeginEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
            parent.onEditingChanged?()
        }
        
        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  !isProgrammaticChange
            else {
                return
            }
            
            let defaultAttrs: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: NSColor.textColor // Or defaultEditorTextColor
            ]
            textView.typingAttributes = defaultAttrs
            
            self.parent.text = textView.string
            self.selectedRanges = textView.selectedRanges
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let onSelectionChange = parent.onSelectionChange,
                  !updatingNSView,
                  let ranges = textView.selectedRanges as? [NSRange]
            else { return }
            selectedRanges = textView.selectedRanges
            DispatchQueue.main.async {
                onSelectionChange(ranges)
            }
        }

        public func textDidEndEditing(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            parent.text = textView.string
            parent.onCommit?()
        }
    }
}

public extension HighlightedTextEditor {
    final class ScrollableTextView: NSView {
        weak var delegate: NSTextViewDelegate?
        
        private var didSetup = false
        
        // MARK: - Text System
        
        private let textStorage: NSTextStorage
        private let layoutManager: NSLayoutManager
        private let textContainer: NSTextContainer
        
        private var highlighter: IncrementalHighlighter?
        
        var selectedRanges: [NSValue] = [] {
            didSet {
                guard !selectedRanges.isEmpty else { return }
                textView.selectedRanges = selectedRanges
            }
        }
        
        public lazy var scrollView: NSScrollView = {
            let scrollView = NSScrollView()
            scrollView.drawsBackground = true
            scrollView.borderType = .noBorder
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalRuler = false
            scrollView.autoresizingMask = [.width, .height]
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            return scrollView
        }()
        
        public lazy var textView: NSTextView = {
            let textView = NSTextView(frame: .zero, textContainer: textContainer)
            textView.autoresizingMask = .width
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.delegate = self.delegate
            textView.drawsBackground = true
            textView.importsGraphics = false
            textView.isHorizontallyResizable = false
            textView.isRichText = false
            textView.isVerticallyResizable = true
            textView.maxSize = NSSize(
                width: CGFloat.greatestFiniteMagnitude,
                height: CGFloat.greatestFiniteMagnitude
            )
            textView.minSize = NSSize(
                width: 0,
                height: scrollView.contentSize.height
            )
            textView.textColor = NSColor.labelColor
            textView.allowsUndo = true
            return textView
        }()
        
        // MARK: - Init
        
        init(highlightRules: [HighlightRule], font: NSFont) {
            let textStorage = NSTextStorage()
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer()
            
            textStorage.addLayoutManager(layoutManager)
            layoutManager.addTextContainer(textContainer)
            
            self.textStorage = textStorage
            self.layoutManager = layoutManager
            self.textContainer = textContainer
            
            super.init(frame: .zero)
            
            self.highlighter = IncrementalHighlighter(
                textStorage: textStorage,
                rules: highlightRules,
                font: font
            )
        }
        
        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // MARK: - Life cycle
        
        override public func viewWillDraw() {
            super.viewWillDraw()
            
            guard !didSetup else { return }
            didSetup = true
            
            setupScrollViewConstraints()
            setupTextView()
        }
        
        func setupScrollViewConstraints() {
            scrollView.translatesAutoresizingMaskIntoConstraints = false
            
            addSubview(scrollView)
            
            NSLayoutConstraint.activate([
                scrollView.topAnchor.constraint(equalTo: topAnchor),
                scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
                scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
                scrollView.leadingAnchor.constraint(equalTo: leadingAnchor)
            ])
        }
        
        func setupTextView() {
            scrollView.documentView = textView
            
            // Ensure the text container wraps at the scroll view width
            if let textContainer = textView.textContainer {
                textContainer.widthTracksTextView = true
                textContainer.containerSize = NSSize(
                    width: scrollView.contentSize.width,
                    height: .greatestFiniteMagnitude
                )
            }
        }
        
        override public func layout() {
            super.layout()
            
            if let textContainer = textView.textContainer {
                textContainer.containerSize = NSSize(
                    width: scrollView.contentSize.width,
                    height: .greatestFiniteMagnitude
                )
            }
        }
        
        // MARK: - External API
        
        func setText(_ text: String) {
            guard textStorage.string != text else { return }
            
            textStorage.beginEditing()
            textStorage.replaceCharacters(
                in: NSRange(location: 0, length: textStorage.length),
                with: text
            )
            textStorage.endEditing()
        }
    }
}

public extension HighlightedTextEditor {
    func introspect(callback: @escaping IntrospectCallback) -> Self {
        var editor = self
        editor.introspect = callback
        return editor
    }

    func onCommit(_ callback: @escaping OnCommitCallback) -> Self {
        var editor = self
        editor.onCommit = callback
        return editor
    }

    func onEditingChanged(_ callback: @escaping OnEditingChangedCallback) -> Self {
        var editor = self
        editor.onEditingChanged = callback
        return editor
    }

    func onTextChange(_ callback: @escaping OnTextChangeCallback) -> Self {
        var editor = self
        editor.onTextChange = callback
        return editor
    }

    func onSelectionChange(_ callback: @escaping OnSelectionChangeCallback) -> Self {
        var editor = self
        editor.onSelectionChange = callback
        return editor
    }

    func onSelectionChange(_ callback: @escaping (_ selectedRange: NSRange) -> Void) -> Self {
        var editor = self
        editor.onSelectionChange = { ranges in
            guard let range = ranges.first else { return }
            callback(range)
        }
        return editor
    }
}

private extension NSRange {
    func clamped(to length: Int) -> NSRange {
        let safeLocation = max(0, min(location, length))
        let maxPossibleLength = length - safeLocation
        let safeLength = max(0, min(self.length, maxPossibleLength))
        return NSRange(location: safeLocation, length: safeLength)
    }
}

@MainActor
final class IncrementalHighlighter: NSObject, @MainActor NSTextStorageDelegate {
    
    private let rules: [HighlightRule]
    private let font: NSFont
    
    private var isHighlighting = false
    
    init(textStorage: NSTextStorage, rules: [HighlightRule], font: NSFont) {
        self.rules = rules
        self.font = font
        
        super.init()
        
        textStorage.delegate = self
        
        rehighlightAll(in: textStorage)
    }
    
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters),
              !isHighlighting
        else { return }
        
        isHighlighting = true
        defer { isHighlighting = false }
        
        let nsString = textStorage.string as NSString
        let fullLength = nsString.length
        
        let padding = 8000 // 2–8k should be ok
        let paddedStart = max(0, editedRange.location - padding)
        let paddedEnd = min(fullLength, editedRange.location + editedRange.length + padding)
        let paddedRange = NSRange(location: paddedStart, length: paddedEnd - paddedStart)
        
        let extendedRange = nsString.paragraphRange(for: paddedRange)
        
        applyHighlighting(in: extendedRange, textStorage: textStorage)
    }
    
    private func rehighlightAll(in textStorage: NSTextStorage) {
        isHighlighting = true
        defer { isHighlighting = false }
        
        let fullText = textStorage.string
        
        let highlighted = HighlightedTextEditor.getHighlightedText(
            text: fullText,
            highlightRules: rules,
            font: font
        )
        
        textStorage.beginEditing()
        textStorage.setAttributedString(highlighted)
        textStorage.endEditing()
    }
    
    private func applyHighlighting(in range: NSRange, textStorage: NSTextStorage) {
        guard range.length > 0 else { return }
        
        let fullContent = textStorage.string as NSString
        let safeRange = NSIntersectionRange(range, NSRange(location: 0, length: fullContent.length))
        
        let substring = fullContent.substring(with: safeRange)
        
        let highlightedSubstring = HighlightedTextEditor.getHighlightedText(
            text: substring,
            highlightRules: rules,
            font: font
        )
        
        textStorage.beginEditing()
        
        let attributesToRemove: [NSAttributedString.Key] = [
            .foregroundColor,
            .font,
            .backgroundColor,
            .underlineStyle
        ]
        
        for attr in attributesToRemove {
            textStorage.removeAttribute(attr, range: safeRange)
        }
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: self.font,
            .foregroundColor: NSColor.textColor
        ]
        textStorage.addAttributes(baseAttributes, range: safeRange)
        
        highlightedSubstring.enumerateAttributes(
            in: NSRange(location: 0, length: highlightedSubstring.length),
            options: []
        ) { attributes, subRange, _ in
            let absoluteRange = NSRange(
                location: safeRange.location + subRange.location,
                length: subRange.length
            )
            
            let filteredAttributes = attributes.filter { $0.key != .paragraphStyle }
            textStorage.addAttributes(filteredAttributes, range: absoluteRange)
        }
        
        textStorage.fixAttributes(in: safeRange)
        textStorage.endEditing()
    }
}
#endif
