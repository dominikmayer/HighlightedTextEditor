//
//  NSFont.swift
//
//
//  Created by Kyle Nazario on 9/8/20.
//  Based on UIFont extension by Maksymilian Wojakowski
//

#if os(macOS)
import AppKit

extension NSFont {
    var bold: NSFont {
        return withTraits(.bold)
    }

    var italic: NSFont {
        return withTraits(.italic)
    }

    var boldItalic: NSFont {
        return withTraits([.bold, .italic])
    }

    func with(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let newTraits = fontDescriptor.symbolicTraits.union(traits)
        let descriptor = fontDescriptor.withSymbolicTraits(newTraits)
        
        return NSFont(descriptor: descriptor, size: self.pointSize) ?? self
    }

    func without(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let newTraits = fontDescriptor.symbolicTraits.subtracting(traits)
        let descriptor = fontDescriptor.withSymbolicTraits(newTraits)
        
        return NSFont(descriptor: descriptor, size: self.pointSize) ?? self
    }
}
#endif
