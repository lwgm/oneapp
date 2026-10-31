import Foundation

enum ISBNValidator {
    /// 识别被拒的原因。区分它的意义在于：不同原因对应的下一步动作完全不同。
    enum Rejection: Equatable {
        /// 含字母等非数字字符（Code128 常见），或完全没有数字。
        case notNumeric
        /// 位数既不是 13 也不是 10（EAN-8、UPC-E 等）。
        case wrongLength
        /// 13 位且校验通过，但前缀不是 978 / 979 —— 这是商品条码。
        case notBookPrefix
        /// 看起来是 ISBN，但校验位不通过 —— 多半没读全，值得再对准一次。
        case failedCheckDigit
    }

    struct RejectionDetail: Equatable {
        /// 原始读数，用于告诉用户「其实读到了什么」。
        let raw: String
        let reason: Rejection
    }

    enum Outcome: Equatable {
        case accepted(String)
        case rejected(RejectionDetail)
    }

    /// 分类一次识别结果，保留失败原因。
    static func classify(_ raw: String) -> Outcome {
        // 字母放在最前面判断：ISBN-10 末位可能是 X，其余字母都说明不是书。
        let hasUnexpectedLetter = raw.uppercased().contains { $0.isLetter && $0 != "X" }
        if hasUnexpectedLetter {
            return .rejected(.init(raw: raw, reason: .notNumeric))
        }

        let cleaned = raw.uppercased().filter { isASCIIDigit($0) || $0 == "X" }
        guard !cleaned.isEmpty else {
            return .rejected(.init(raw: raw, reason: .notNumeric))
        }
        guard cleaned.count == 13 || cleaned.count == 10 else {
            return .rejected(.init(raw: raw, reason: .wrongLength))
        }

        if cleaned.count == 13 {
            guard cleaned.hasPrefix("978") || cleaned.hasPrefix("979") else {
                return .rejected(.init(raw: raw, reason: .notBookPrefix))
            }
            guard isValid13(cleaned) else {
                return .rejected(.init(raw: raw, reason: .failedCheckDigit))
            }
            return .accepted(cleaned)
        }

        guard isValid10(cleaned) else {
            return .rejected(.init(raw: raw, reason: .failedCheckDigit))
        }
        return .accepted(cleaned)
    }

    /// 从条码原始值中提取合法 ISBN。非法或非书籍条码返回 nil。
    static func normalized(_ raw: String) -> String? {
        guard case .accepted(let code) = classify(raw) else { return nil }
        return code
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
