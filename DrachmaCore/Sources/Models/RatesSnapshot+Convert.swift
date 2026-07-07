import Foundation

public enum ConversionError: Error, Equatable, Sendable {
    case unknownCurrency(String)
}

extension RatesSnapshot {
    /// Convert an amount between any two currencies quoted in this snapshot.
    /// The snapshot's base currency participates naturally (rate 1), so
    /// base→quote, quote→base, and quote→quote cross rates all work.
    public func convert(_ amount: Decimal, from source: String, to target: String) throws -> Decimal {
        let src = source.uppercased()
        let dst = target.uppercased()

        func rate(_ code: String) throws -> Decimal {
            if code == base.uppercased() { return 1 }
            guard let rate = rates[code] else { throw ConversionError.unknownCurrency(code) }
            return rate
        }

        if src == dst { return amount }
        return amount * (try rate(dst)) / (try rate(src))
    }
}
