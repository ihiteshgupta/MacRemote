import Foundation
import CommonCrypto

enum RFBAuthError: Error, LocalizedError {
    case invalidChallenge
    case authenticationFailed
    case unsupportedSecurityType
    case connectionClosed

    var errorDescription: String? {
        switch self {
        case .invalidChallenge:
            return "Invalid authentication challenge from server"
        case .authenticationFailed:
            return "Authentication failed. Check your password."
        case .unsupportedSecurityType:
            return "Server requires unsupported authentication method"
        case .connectionClosed:
            return "Connection closed by server"
        }
    }
}

struct RFBAuth {

    // MARK: - VNC Authentication (DES challenge-response)

    /// Performs VNC DES authentication
    /// - Parameters:
    ///   - challenge: 16-byte challenge from server
    ///   - password: User's VNC password
    /// - Returns: 16-byte response
    static func vncAuth(challenge: Data, password: String) -> Data {
        guard challenge.count == 16 else {
            return Data(count: 16)
        }

        // VNC uses a reversed bit order for the DES key
        let key = prepareVNCKey(password: password)

        // Encrypt the challenge with DES
        var response = Data(count: 16)

        // First 8 bytes
        let encrypted1 = desEncrypt(data: Data(challenge[0..<8]), key: key)
        response.replaceSubrange(0..<8, with: encrypted1)

        // Second 8 bytes
        let encrypted2 = desEncrypt(data: Data(challenge[8..<16]), key: key)
        response.replaceSubrange(8..<16, with: encrypted2)

        return response
    }

    /// Prepares VNC DES key by reversing bit order
    private static func prepareVNCKey(password: String) -> Data {
        var keyBytes = [UInt8](repeating: 0, count: 8)
        let passwordBytes = Array(password.utf8)

        for i in 0..<min(8, passwordBytes.count) {
            keyBytes[i] = reverseBits(passwordBytes[i])
        }

        return Data(keyBytes)
    }

    /// Reverses bit order in a byte (VNC quirk)
    private static func reverseBits(_ byte: UInt8) -> UInt8 {
        var result: UInt8 = 0
        var b = byte
        for _ in 0..<8 {
            result = (result << 1) | (b & 1)
            b >>= 1
        }
        return result
    }

    /// DES encrypt using CommonCrypto
    private static func desEncrypt(data: Data, key: Data) -> Data {
        var outLength = 0
        var outBytes = [UInt8](repeating: 0, count: 8)

        let keyBytes = [UInt8](key)
        let dataBytes = [UInt8](data)

        CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmDES),
            CCOptions(kCCOptionECBMode),
            keyBytes, kCCKeySizeDES,
            nil,  // no IV for ECB
            dataBytes, 8,
            &outBytes, 8,
            &outLength
        )

        return Data(outBytes)
    }

    // MARK: - Apple Remote Desktop (Diffie-Hellman)

    /// Performs ARD (Apple Remote Desktop) authentication
    /// Uses Diffie-Hellman key exchange with AES-128-ECB encrypted credentials
    /// Protocol: https://github.com/nmap/nmap/blob/master/nselib/vnc.lua
    static func ardAuth(
        generator: UInt16,
        keyLength: UInt16,
        prime: Data,
        peerKey: Data,
        username: String,
        password: String
    ) -> (publicKey: Data, credentials: Data)? {
        let keyLen = Int(keyLength)

        print("ARD Auth: generator=\(generator), keyLen=\(keyLen) (\(keyLen * 8) bits), prime=\(prime.count) bytes, peerKey=\(peerKey.count) bytes")

        // 1. Generate random private key
        // Use 16 bytes (128 bits) for speed - still secure for session keys
        // Note: Pure Swift bignum is slow; a proper implementation would use OpenSSL or GMP
        let privateKeyLen = min(16, keyLen)
        var privateKeyBytes = [UInt8](repeating: 0, count: privateKeyLen)
        guard SecRandomCopyBytes(kSecRandomDefault, privateKeyLen, &privateKeyBytes) == errSecSuccess else {
            print("ARD Auth: Failed to generate private key")
            return nil
        }
        // Pad to keyLen for modPow
        var privateKey = [UInt8](repeating: 0, count: keyLen - privateKeyLen) + privateKeyBytes
        print("ARD Auth: Generated \(privateKeyLen * 8)-bit private key")

        // 2. Compute public key: generator^privateKey mod prime
        print("ARD Auth: Computing public key (this may take a moment)...")
        let pubKeyStart = CFAbsoluteTimeGetCurrent()
        guard let publicKey = modPow(
            base: bigIntFromUInt16(generator, length: keyLen),
            exponent: Data(privateKey),
            modulus: prime
        ) else {
            print("ARD Auth: Failed to compute public key")
            return nil
        }
        print("ARD Auth: Public key computed in \(CFAbsoluteTimeGetCurrent() - pubKeyStart)s")

        // 3. Compute shared secret: peerKey^privateKey mod prime
        print("ARD Auth: Computing shared secret...")
        let secretStart = CFAbsoluteTimeGetCurrent()
        guard let sharedSecret = modPow(
            base: peerKey,
            exponent: Data(privateKey),
            modulus: prime
        ) else {
            print("ARD Auth: Failed to compute shared secret")
            return nil
        }
        print("ARD Auth: Shared secret computed in \(CFAbsoluteTimeGetCurrent() - secretStart)s")

        // 4. MD5 hash of shared secret -> AES key
        var md5Hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        sharedSecret.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(sharedSecret.count), &md5Hash)
        }

        // 5. Prepare credentials: 64 bytes username + 64 bytes password (null padded)
        var credentials = Data(count: 128)
        let usernameBytes = Array(username.utf8.prefix(63))
        let passwordBytes = Array(password.utf8.prefix(63))
        credentials.replaceSubrange(0..<usernameBytes.count, with: usernameBytes)
        credentials.replaceSubrange(64..<(64 + passwordBytes.count), with: passwordBytes)

        // 6. AES-128-ECB encrypt credentials (no IV for ECB mode)
        var encryptedCredentials = [UInt8](repeating: 0, count: 128)
        var encryptedLength = 0

        let status = CCCrypt(
            CCOperation(kCCEncrypt),
            CCAlgorithm(kCCAlgorithmAES),
            CCOptions(kCCOptionECBMode), // ECB mode, no padding needed
            md5Hash, kCCKeySizeAES128,
            nil, // No IV for ECB
            [UInt8](credentials), 128,
            &encryptedCredentials, 128,
            &encryptedLength
        )

        guard status == kCCSuccess else {
            print("ARD Auth: AES encryption failed with status \(status)")
            return nil
        }

        print("ARD Auth: Successfully encrypted credentials, publicKey=\(publicKey.count) bytes")

        // Return public key and encrypted credentials (no IV prefix for ECB)
        return (publicKey: publicKey, credentials: Data(encryptedCredentials))
    }

    // MARK: - Big Integer Helpers (simplified for ARD)

    /// Convert UInt16 to big-endian Data of specified length
    private static func bigIntFromUInt16(_ value: UInt16, length: Int) -> Data {
        var result = Data(count: length)
        result[length - 2] = UInt8((value >> 8) & 0xFF)
        result[length - 1] = UInt8(value & 0xFF)
        return result
    }

    /// Modular exponentiation: base^exponent mod modulus
    /// Simplified implementation using Swift's built-in arithmetic
    /// Note: This only works for small key lengths. For production, use a proper bignum library.
    private static func modPow(base: Data, exponent: Data, modulus: Data) -> Data? {
        // Convert to arrays for easier manipulation
        let baseBytes = [UInt8](base)
        var expBytes = [UInt8](exponent)
        let modBytes = [UInt8](modulus)

        // Strip leading zeros from exponent for efficiency
        while expBytes.count > 1 && expBytes[0] == 0 {
            expBytes.removeFirst()
        }

        // Initialize result as 1
        var result = [UInt8](repeating: 0, count: modBytes.count)
        result[result.count - 1] = 1

        var baseCopy = baseBytes

        // Square-and-multiply algorithm (right-to-left binary method)
        // Process only the significant bytes of the exponent
        for byte in expBytes.reversed() {
            for bit in 0..<8 {
                if (byte >> bit) & 1 == 1 {
                    result = bigMulMod(result, baseCopy, modBytes)
                }
                baseCopy = bigMulMod(baseCopy, baseCopy, modBytes)
            }
        }

        return Data(result)
    }

    /// Big integer multiplication with modulo
    private static func bigMulMod(_ a: [UInt8], _ b: [UInt8], _ mod: [UInt8]) -> [UInt8] {
        let n = mod.count
        var result = [UInt16](repeating: 0, count: n * 2)

        // Multiply
        for i in 0..<n {
            for j in 0..<n {
                let idx = n * 2 - 1 - i - j
                result[idx] += UInt16(a[n - 1 - i]) * UInt16(b[n - 1 - j])

                // Propagate carry
                var k = idx
                while k > 0 && result[k] > 255 {
                    result[k - 1] += result[k] >> 8
                    result[k] &= 0xFF
                    k -= 1
                }
            }
        }

        // Convert back to bytes
        var product = result.map { UInt8($0 & 0xFF) }

        // Reduce mod
        return bigMod(product, mod)
    }

    /// Big integer modulo using shift-and-subtract division with quotient estimation
    private static func bigMod(_ a: [UInt8], _ mod: [UInt8]) -> [UInt8] {
        // Strip leading zeros from mod
        var modStripped = mod
        while modStripped.count > 1 && modStripped[0] == 0 {
            modStripped.removeFirst()
        }

        var result = a

        // Strip leading zeros from result
        while result.count > 1 && result[0] == 0 {
            result.removeFirst()
        }

        // If result < mod, we're done
        if bigCompare(result, modStripped) < 0 {
            while result.count < mod.count {
                result.insert(0, at: 0)
            }
            return result
        }

        let modLen = modStripped.count
        let modHigh = UInt32(modStripped[0])
        let modHigh2 = modLen > 1 ? (UInt32(modStripped[0]) << 8) | UInt32(modStripped[1]) : UInt32(modStripped[0]) << 8

        // Long division with quotient estimation
        while bigCompare(result, modStripped) >= 0 {
            // Strip leading zeros
            while result.count > 1 && result[0] == 0 {
                result.removeFirst()
            }

            if bigCompare(result, modStripped) < 0 {
                break
            }

            let resultLen = result.count
            let shift = resultLen - modLen

            if shift < 0 {
                break
            }

            // Estimate quotient digit using top bytes
            var q: UInt32
            if shift == 0 {
                // Direct comparison case
                let resultHigh2 = resultLen > 1 ? (UInt32(result[0]) << 8) | UInt32(result[1]) : UInt32(result[0]) << 8
                q = resultHigh2 / (modHigh + 1)
                if q == 0 { q = 1 }
            } else {
                // Shifted case - estimate from top 2 bytes
                let resultHigh2 = resultLen > 1 ? (UInt32(result[0]) << 8) | UInt32(result[1]) : UInt32(result[0]) << 8
                q = min(255, resultHigh2 / (modHigh + 1))
                if q == 0 { q = 1 }
            }

            // Create shifted mod * q
            var modShifted = [UInt8](repeating: 0, count: resultLen)

            // Multiply mod by q and place at shift position
            var carry: UInt32 = 0
            for i in (0..<modLen).reversed() {
                let prod = UInt32(modStripped[i]) * q + carry
                let destIdx = i + shift
                if destIdx < resultLen {
                    modShifted[destIdx] = UInt8(prod & 0xFF)
                }
                carry = prod >> 8
            }
            // Handle remaining carry
            var carryIdx = shift - 1
            while carry > 0 && carryIdx >= 0 {
                modShifted[carryIdx] = UInt8(carry & 0xFF)
                carry >>= 8
                carryIdx -= 1
            }

            // Ensure we don't subtract more than result
            if bigCompare(result, modShifted) < 0 {
                // q was too large, use q=1 (just subtract shifted mod once)
                modShifted = [UInt8](repeating: 0, count: resultLen)
                for i in 0..<modLen {
                    let destIdx = i + shift
                    if destIdx < resultLen {
                        modShifted[destIdx] = modStripped[i]
                    }
                }
                // Check again
                if bigCompare(result, modShifted) < 0 && shift > 0 {
                    // Need to shift one less
                    modShifted = [UInt8](repeating: 0, count: resultLen)
                    for i in 0..<modLen {
                        let destIdx = i + shift - 1
                        if destIdx < resultLen {
                            modShifted[destIdx] = modStripped[i]
                        }
                    }
                }
            }

            if bigCompare(result, modShifted) >= 0 {
                result = bigSub(result, modShifted)
            } else {
                // Fallback: subtract just mod
                if bigCompare(result, modStripped) >= 0 {
                    result = bigSub(result, modStripped)
                } else {
                    break
                }
            }
        }

        // Ensure result has same length as mod
        while result.count < mod.count {
            result.insert(0, at: 0)
        }
        while result.count > mod.count {
            result.removeFirst()
        }

        return result
    }

    /// Compare two big integers
    private static func bigCompare(_ a: [UInt8], _ b: [UInt8]) -> Int {
        let maxLen = max(a.count, b.count)
        let aPadded = [UInt8](repeating: 0, count: maxLen - a.count) + a
        let bPadded = [UInt8](repeating: 0, count: maxLen - b.count) + b

        for i in 0..<maxLen {
            if aPadded[i] > bPadded[i] { return 1 }
            if aPadded[i] < bPadded[i] { return -1 }
        }
        return 0
    }

    /// Subtract b from a (assuming a >= b)
    private static func bigSub(_ a: [UInt8], _ b: [UInt8]) -> [UInt8] {
        let maxLen = max(a.count, b.count)
        var aPadded = [UInt8](repeating: 0, count: maxLen - a.count) + a
        let bPadded = [UInt8](repeating: 0, count: maxLen - b.count) + b

        var borrow: Int = 0
        for i in (0..<maxLen).reversed() {
            let diff = Int(aPadded[i]) - Int(bPadded[i]) - borrow
            if diff < 0 {
                aPadded[i] = UInt8(diff + 256)
                borrow = 1
            } else {
                aPadded[i] = UInt8(diff)
                borrow = 0
            }
        }

        return aPadded
    }

    // MARK: - Parse Security Types

    static func parseSecurityTypes(data: Data) -> [RFBSecurityType] {
        guard !data.isEmpty else { return [] }

        // RFB 3.7+ format: first byte is count, then type bytes
        let count = Int(data[0])
        guard data.count >= count + 1 else { return [] }

        var types: [RFBSecurityType] = []
        for i in 1...count {
            if let type = RFBSecurityType(rawValue: data[i]) {
                types.append(type)
            }
        }
        return types
    }

    /// Choose best security type from available options
    static func chooseBestSecurityType(_ types: [RFBSecurityType]) -> RFBSecurityType? {
        // Preference order: VNC auth > ARD/macOS auth > none
        // NOTE: ARD auth requires Diffie-Hellman with 1024-bit keys. The pure Swift
        // bignum implementation is too slow. A production implementation would use
        // OpenSSL or a dedicated bigint library. For now, prefer VNC auth.
        let preference: [RFBSecurityType] = [.vncAuth, .appleDH, .macOSAuth, .none]

        for preferred in preference {
            if types.contains(preferred) {
                return preferred
            }
        }

        return types.first
    }

    // MARK: - Parse Auth Result

    static func parseAuthResult(data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let result = UInt32(bigEndian: data)
        return result == 0  // 0 = OK, 1 = Failed
    }
}
