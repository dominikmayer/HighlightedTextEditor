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
        let textView = ScrollableTextView()
        textView.delegate = context.coordinator
        runIntrospect(textView)

        return textView
    }

    public func updateNSView(_ view: ScrollableTextView, context: Context) {
        context.coordinator.updatingNSView = true
        
        let needsHighlight = context.coordinator.lastPlainText != text
        
        let highlightedText: NSAttributedString
        if needsHighlight {
            let newHighlighted = HighlightedTextEditor.getHighlightedText(
                text: text,
                highlightRules: highlightRules,
                font: font
            )
            context.coordinator.lastPlainText = text
            context.coordinator.lastHighlightedText = newHighlighted
            highlightedText = newHighlighted
        } else {
            highlightedText = context.coordinator.lastHighlightedText
        }
        
        let currentString = view.textView.string
        let newString = highlightedText.string
        
        let lengthsDiffer = (currentString as NSString).length != highlightedText.length
        
        if currentString != newString || lengthsDiffer {
            context.coordinator.isProgrammaticChange = true
            
            view.attributedText = highlightedText
            
            let validRanges = context.coordinator.selectedRanges.map { value -> NSValue in
                let range = value.rangeValue
                let safeRange = range.clamped(to: highlightedText.length)
                return NSValue(range: safeRange)
            }
            view.selectedRanges = validRanges
        }
        else if view.textView.attributedString() != highlightedText {
            context.coordinator.isProgrammaticChange = true
            
            view.textView.textStorage?.beginEditing()
            highlightedText.enumerateAttributes(in: NSRange(location: 0, length: highlightedText.length), options: []) { (attrs, range, _) in
                view.textView.textStorage?.setAttributes(attrs, range: range)
            }
            view.textView.textStorage?.endEditing()
        }
        
        guard highlightedText.length > 0 else {
            view.textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
            context.coordinator.isProgrammaticChange = false
            context.coordinator.updatingNSView = false
            return
        }
        
        if let insertionIndex = view.selectedRanges.first?.rangeValue.location {
            let safeIndex = max(0, min(insertionIndex, highlightedText.length - 1))
            
            var attributes = highlightedText.attributes(at: safeIndex, effectiveRange: nil)
            if attributes[.font] == nil {
                attributes[.font] = font
            }
            view.textView.typingAttributes = attributes
        } else {
            view.textView.typingAttributes = [.font: font, .foregroundColor: NSColor.textColor]
        }
        
        context.coordinator.isProgrammaticChange = false
        context.coordinator.updatingNSView = false
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
        
        var attributedText: NSAttributedString {
            didSet {
                textView.textStorage?.setAttributedString(attributedText)
            }
        }

        var selectedRanges: [NSValue] = [] {
            didSet {
                guard selectedRanges.count > 0 else {
                    return
                }

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
            let contentSize = scrollView.contentSize
            let textStorage = NSTextStorage()

            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)

            let textContainer = NSTextContainer(containerSize: scrollView.frame.size)
            textContainer.widthTracksTextView = true
            textContainer.containerSize = NSSize(
                width: contentSize.width,
                height: CGFloat.greatestFiniteMagnitude
            )

            layoutManager.addTextContainer(textContainer)

            let textView = NSTextView(frame: .zero, textContainer: textContainer)
            textView.autoresizingMask = .width
            textView.backgroundColor = NSColor.textBackgroundColor
            textView.delegate = self.delegate
            textView.drawsBackground = true
            textView.importsGraphics = false
            textView.isHorizontallyResizable = false
            textView.isRichText = false
            textView.isVerticallyResizable = true
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView.minSize = NSSize(width: 0, height: contentSize.height)
            textView.textColor = NSColor.labelColor
            textView.allowsUndo = true

            return textView
        }()

        // MARK: - Init
        init() {
            self.attributedText = NSMutableAttributedString()

            super.init(frame: .zero)
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
#endif
