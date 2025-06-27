/* 
 * QR Code generator library (Swift)
 * 
 * Copyright (c) Project Nayuki. (MIT License)
 * https://www.nayuki.io/page/qr-code-generator-library
 * Copyright (c) 2020 fwcd
 * 
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 * - The above copyright notice and this permission notice shall be included in
 *   all copies or substantial portions of the Software.
 * - The Software is provided "as is", without warranty of any kind, express or
 *   implied, including but not limited to the warranties of merchantability,
 *   fitness for a particular purpose and noninfringement. In no event shall the
 *   authors or copyright holders be liable for any claim, damages or other
 *   liability, whether in an action of contract, tort or otherwise, arising from,
 *   out of or in connection with the Software or the use or other dealings in the
 *   Software.
 */

/// An appendable sequence of bits (0s and 1s).
public struct BitBuffer {
    public var bits: [Bool]
    public var count: UInt { UInt(bits.count) }
    
    public init(_ bits: [Bool] = []) {
        self.bits = bits
    }

    /// Appends the given number of low-order bits of the given value to this buffer.
    /// 
    /// Requires len &#x2264; 31 and val &lt; 2<sup>len</sup>.
    public mutating func appendBits(_ value: UInt32, _ length: Int) {
        assert(length <= 31 && (value >> length) == 0, "Value out of range")
        bits += (0..<length).reversed().map { getBit(value, Int32($0)) }
    }
}

/// Returns true iff the i'th bit of x is set to 1.
func getBit(_ x: UInt32, _ i: Int32) -> Bool {
    (x >> i) & 1 != 0
}
