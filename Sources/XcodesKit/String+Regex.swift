//
//  String+Regex.swift
//  XcodesKit
//
//  Created by Ruslan Alikhamov on 01.12.2020.
//

import Foundation

extension String {
    
    func value(regex: String, template: String) -> Float? {
        guard let match = self.groupMatch(regex: regex, group: template)
        else {
            return nil
        }
        return Float(self[match])
    }
    
}

extension String {
    
    func matches(regex: String) -> [NSTextCheckingResult]? {
        guard let percentRegex = try? NSRegularExpression(pattern: regex) else {
            return nil
        }
        let totalRange = NSRange(location: 0, length: self.count)
        let percentMatches = percentRegex.matches(in: self, options: [], range: totalRange)
        return percentMatches
    }
    
    func firstMatch(regex: String) -> NSTextCheckingResult? {
        let found = self.matches(regex: regex)
        guard let first = found?.first else {
            return nil
        }
        return first
    }
    
    func groupMatch(regex: String, group: String) -> Range<String.Index>? {
        guard let found = self.firstMatch(regex: regex) else {
            return nil
        }
        return Range(found.range(withName: group), in: self)
    }
    
    func percentMatch(regex: String) -> Range<String.Index>? {
        self.groupMatch(regex: regex, group: "percent")
    }
    
    func string(from range: NSRange) -> String? {
        let startIndex = self.startIndex
        let offsetIndex = self.index(startIndex, offsetBy: range.location)
        let endIndex = self.index(offsetIndex, offsetBy: range.length - 1)
        return String(self[offsetIndex ... endIndex])
    }
    
}
