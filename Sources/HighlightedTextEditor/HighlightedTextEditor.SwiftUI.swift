//
//  HighlightedTextEditor.SwiftUI.swift
//  HighlightedTextEditor
//
//  Created by Dominik Mayer on 01.12.25.
//

import SwiftUI

public typealias AttributeBuilder = @Sendable (Font) -> AttributeContainer

public struct AttributeStyle: Sendable {
    let make: @Sendable (Font) -> AttributeContainer

    public init(
        make: @escaping @Sendable (Font) -> AttributeContainer
    ) {
        self.make = make
    }

    public func callAsFunction(_ font: Font) -> AttributeContainer {
        make(font)
    }

    public static let plain = AttributeStyle { _ in
        AttributeContainer()
    }

    public static let bold = AttributeStyle { font in
        var container = AttributeContainer()
        container.font = font.weight(.bold)
        return container
    }

    public static let italic = AttributeStyle { font in
        var container = AttributeContainer()
        container.font = font.italic()
        return container
    }
}

public extension AttributeStyle {
    func foreground(_ color: Color) -> AttributeStyle {
        AttributeStyle { font in
            var attributes = self.make(font)
            attributes.foregroundColor = color
            return attributes
        }
    }

    func background(_ color: Color) -> AttributeStyle {
        AttributeStyle { font in
            var attributes = self.make(font)
            attributes.backgroundColor = color
            return attributes
        }
    }

    func underline(_ style: Text.LineStyle) -> AttributeStyle {
        AttributeStyle { font in
            var attributes = self.make(font)
            attributes.underlineStyle = style
            return attributes
        }
    }
}

public struct NewHighlightRule: Sendable {
    let regex: NSRegularExpression
    let style: AttributeStyle

    public init?(
        pattern: String,
        options: NSRegularExpression.Options = [],
        style: AttributeStyle
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        self.regex = regex
        self.style = style
    }

    func attributes(for font: Font) -> AttributeContainer {
        style(font)
    }
}

func makeHighlightedText(
    from text: String,
    using rules: [NewHighlightRule],
    baseFont: Font
) -> AttributedString {
    var attributed = AttributedString(text)
    attributed.font = baseFont

    let plain = String(attributed.characters)
    let fullRange = NSRange(plain.startIndex..<plain.endIndex, in: plain)

    for rule in rules {
        let matches = rule.regex.matches(in: plain, options: [], range: fullRange)
        let ruleAttributes = rule.attributes(for: baseFont)

        for match in matches {
            guard let stringRange = Range(match.range, in: plain),
                  let attributedRange = Range(stringRange, in: attributed)
            else { continue }

            attributed[attributedRange].mergeAttributes(ruleAttributes)
        }
    }

    return attributed
}

public struct SwiftUIHighlightedTextEditor: View {
    @Binding var text: String

    let highlightRules: [NewHighlightRule]
    let font: Font

    @State private var richText: AttributedString
    @State private var selection = AttributedTextSelection()
    @State private var isProgrammaticChange = false

    public init(
        text: Binding<String>,
        highlightRules: [NewHighlightRule],
        font: Font = .system(.body, design: .monospaced)
    ) {
        self._text = text
        self.highlightRules = highlightRules
        self.font = font

        _richText = State(
            initialValue: makeHighlightedText(
                from: text.wrappedValue,
                using: highlightRules,
                baseFont: font
            )
        )
    }

    public var body: some View {
        TextEditor(text: $richText, selection: $selection)
            .font(font)
            .onChange(of: text) { newValue in
                guard !isProgrammaticChange else { return }

                isProgrammaticChange = true
                richText = makeHighlightedText(
                    from: newValue,
                    using: highlightRules,
                    baseFont: font
                )
                isProgrammaticChange = false
            }
            .onChange(of: richText) { newValue in
                guard !isProgrammaticChange else { return }

                let plain = String(newValue.characters)

                text = plain

                isProgrammaticChange = true
                richText = makeHighlightedText(
                    from: plain,
                    using: highlightRules,
                    baseFont: font
                )
                isProgrammaticChange = false
            }
    }
}
