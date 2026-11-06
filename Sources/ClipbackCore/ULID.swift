import Foundation

/// Lexicographically sortable unique ids: 48 bits of milliseconds then 80 random bits, Crockford base32.
public enum ULID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func make(date: Date = Date()) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(date: date, using: &generator)
    }

    public static func make<G: RandomNumberGenerator>(date: Date, using generator: inout G) -> String {
        var time = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var timeChars = [Character](repeating: "0", count: 10)
        for index in stride(from: 9, through: 0, by: -1) {
            timeChars[index] = alphabet[Int(time & 31)]
            time >>= 5
        }
        let randomChars = (0..<16).map { _ in alphabet[Int(generator.next() & 31)] }
        return String(timeChars + randomChars)
    }
}
