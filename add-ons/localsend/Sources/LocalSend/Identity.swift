import CryptoKit
import Foundation
import Security

/// This Mac's LocalSend identity: a self-signed certificate, the same kind LocalSend makes (RSA-2048,
/// "CN=LocalSend User"), kept in the add-on's folder. Its SHA-256 is the fingerprint other devices pin, so it's made
/// once and kept.
struct Identity {
    let identity: SecIdentity
    let certificate: SecCertificate
    /// Uppercase hex SHA-256 of the certificate, as LocalSend writes it.
    let fingerprint: String

    struct Failure: Error, CustomStringConvertible { let description: String }

    // The PKCS #12 only lives in the add-on's own folder, readable by this user alone; the password just satisfies
    // the format.
    private static let password = "ledge-localsend"

    static func load(from folder: URL) throws -> Identity {
        let p12 = folder.appendingPathComponent("identity.p12")
        if !FileManager.default.fileExists(atPath: p12.path) { try make(p12, in: folder) }
        let data = try Data(contentsOf: p12)
        var options: [String: Any] = [kSecImportExportPassphrase as String: password]
        // Kept in memory, not added to the login keychain, where macOS lets us.
        if #available(macOS 15.0, *) { options[kSecImportToMemoryOnly as String] = true }
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess, let first = (items as? [[String: Any]])?.first,
              let found = first[kSecImportItemIdentity as String] else {
            throw Failure(description: "Couldn't read the certificate (\(status)).")
        }
        let identity = found as! SecIdentity
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let certificate else { throw Failure(description: "The identity has no certificate.") }
        return Identity(identity: identity, certificate: certificate, fingerprint: Self.fingerprint(of: certificate))
    }

    static func fingerprint(of certificate: SecCertificate) -> String {
        SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02X", $0) }.joined()
    }

    /// Makes the key and certificate with macOS's own openssl, then bundles them; the loose key is deleted.
    private static func make(_ p12: URL, in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let key = folder.appendingPathComponent("key.pem"), cert = folder.appendingPathComponent("cert.pem")
        let config = folder.appendingPathComponent("cert.cnf")
        defer { for file in [key, config] { try? FileManager.default.removeItem(at: file) } }
        // An X.509 v3 certificate: without extensions openssl writes v1, which LocalSend 1.18's TLS (webpki)
        // refuses, dropping the connection.
        try """
            [req]
            distinguished_name = dn
            x509_extensions = v3
            prompt = no
            [dn]
            CN = LocalSend User
            [v3]
            basicConstraints = critical,CA:FALSE
            keyUsage = critical,digitalSignature,keyEncipherment
            extendedKeyUsage = serverAuth,clientAuth
            subjectKeyIdentifier = hash
            """.write(to: config, atomically: true, encoding: .utf8)
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "36500", "-config", config.path,
                     "-keyout", key.path, "-out", cert.path])
        try openssl(["pkcs12", "-export", "-inkey", key.path, "-in", cert.path, "-out", p12.path, "-passout", "pass:\(password)"])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: p12.path)
    }

    private static func openssl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "openssl \(arguments[0]) failed.") }
    }
}
