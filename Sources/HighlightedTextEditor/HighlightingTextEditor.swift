//
//  HighlightingTextEditor.swift
//
//
//  Created by Kyle Nazario on 8/31/20.
//

import SwiftUI

#if os(macOS)
import AppKit

public typealias SystemFontAlias = NSFont
public typealias SystemColorAlias = NSColor
public typealias SymbolicTraits = NSFontDescriptor.SymbolicTraits
public typealias SystemTextView = NSTextView
public typealias SystemScrollView = NSScrollView

public let defaultEditorFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
let defaultEditorTextColor = NSColor.labelColor

#else
import UIKit

public typealias SystemFontAlias = UIFont
public typealias SystemColorAlias = UIColor
public typealias SymbolicTraits = UIFontDescriptor.SymbolicTraits
public typealias SystemTextView = UITextView
public typealias SystemScrollView = UIScrollView

public let defaultEditorFont = UIFont.preferredFont(forTextStyle: .body)
let defaultEditorTextColor = UIColor.label

#endif

extension SystemFontAlias: @unchecked Sendable {}

public struct TextFormattingRule: Sendable {
    public typealias AttributedKeyCallback = @Sendable (String, Range<String.Index>) -> Any

    let key: NSAttributedString.Key?
    let calculateValue: AttributedKeyCallback?
    let fontTraits: SymbolicTraits

    // ------------------- convenience ------------------------

    public init(key: NSAttributedString.Key, value: Sendable) {
        self.init(key: key, calculateValue: { _, _ in value }, fontTraits: [])
    }

    public init(key: NSAttributedString.Key, calculateValue: @escaping AttributedKeyCallback) {
        self.init(key: key, calculateValue: calculateValue, fontTraits: [])
    }

    public init(fontTraits: SymbolicTraits) {
        self.init(key: nil, fontTraits: fontTraits)
    }

    // ------------------ most powerful initializer ------------------

    init(
        key: NSAttributedString.Key? = nil,
        calculateValue: AttributedKeyCallback? = nil,
        fontTraits: SymbolicTraits = []
    ) {
        self.key = key
        self.calculateValue = calculateValue
        self.fontTraits = fontTraits
    }
}

public struct HighlightRule: Sendable {
    let pattern: NSRegularExpression

    let formattingRules: [TextFormattingRule]

    // ------------------- convenience ------------------------

    public init(pattern: NSRegularExpression, formattingRule: TextFormattingRule) {
        self.init(pattern: pattern, formattingRules: [formattingRule])
    }

    // ------------------ most powerful initializer ------------------

    public init(pattern: NSRegularExpression, formattingRules: [TextFormattingRule]) {
        self.pattern = pattern
        self.formattingRules = formattingRules
    }
}

internal protocol HighlightingTextEditor {
    var text: String { get set }
    var highlightRules: [HighlightRule] { get }
    var font: SystemFontAlias { get }
}

public typealias OnSelectionChangeCallback = ([NSRange]) -> Void
public typealias IntrospectCallback = (_ editor: HighlightedTextEditor.Internals) -> Void
public typealias EmptyCallback = () -> Void
public typealias OnCommitCallback = EmptyCallback
public typealias OnEditingChangedCallback = EmptyCallback
public typealias OnTextChangeCallback = (_ editorContent: String) -> Void

extension HighlightingTextEditor {
    var placeholderFont: SystemColorAlias { SystemColorAlias() }

    static func getHighlightedText(
        text: String,
        highlightRules: [HighlightRule],
        font: SystemFontAlias
    ) -> NSMutableAttributedString {
        let highlightedString = NSMutableAttributedString(string: text)
        // Always use utf16.count for NSRange compatibility
        let fullRange = NSRange(location: 0, length: (text as NSString).length)

        highlightedString.addAttribute(.font, value: font, range: fullRange)
        highlightedString.addAttribute(.foregroundColor, value: defaultEditorTextColor, range: fullRange)

        for rule in highlightRules {
            let matches = rule.pattern.matches(in: text, options: [], range: fullRange)
            for match in matches {
                for formattingRule in rule.formattingRules {
                    
                    var currentFont = font
                    highlightedString.enumerateAttribute(.font, in: match.range, options: []) { value, _, _ in
                        if let oldFont = value as? SystemFontAlias {
                            currentFont = oldFont.with(formattingRule.fontTraits)
                        }
                    }
                    highlightedString.addAttribute(.font, value: currentFont, range: match.range)

                    if let key = formattingRule.key,
                       let calculateValue = formattingRule.calculateValue,
                       let stringRange = Range(match.range, in: text) {
                        
                        let matchContent = String(text[stringRange])
                        let value = calculateValue(matchContent, stringRange)
                        highlightedString.addAttribute(key, value: value, range: match.range)
                    }
                }
            }
        }
        return highlightedString
    }
}
