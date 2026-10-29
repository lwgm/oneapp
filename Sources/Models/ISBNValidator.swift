import Foundation

enum ISBNValidator {
    /// 从条码原始值中提取合法 ISBN。非法或非书籍条码返回 nil。
    static func normalized(_ raw: String) -> String? {
        let cleaned = raw.uppercased().filter { isASCIIDigit($0) || $0 == "X" }

        if cleaned.count == 13,
           cleaned.hasPrefix("978") || cleaned.hasPrefix("979"),
           isValid13(cleaned) {
            return cleaned
        }

        if cleaned.count == 10, isValid10(cleaned) {
            return cleaned
        }

        return nil
    }

    static func isValid13(_ code: String) -> Bool {
        guard code.count == 13 else { return false }

        var sum = 0
        for (index, character) in code.enumerated() {
            guard let ascii = character.asciiValue, ascii >= 48, ascii <= 57 else { return false }
            let digit = Int(ascii - 48)
            if index < 12 {
                sum += digit * (index % 2 == 0 ? 1 : 3)
            } else {
                return (10 - sum % 10) % 10 == digit
            }
        }
        return false
    }

    static func isValid10(_ code: String) -> Bool {
        guard code.count == 10 else { return false }

        var total = 0
        for (index, character) in code.enumerated() {
            let value: Int
            if character == "X" {
                guard index == 9 else { return false }
                value = 10
            } else if let ascii = character.asciiValue, ascii >= 48, ascii <= 57 {
                value = Int(ascii - 48)
            } else {
                return false
            }
            total += value * (10 - index)
        }
        return total % 11 == 0
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return ascii >= 48 && ascii <= 57
    }
}
