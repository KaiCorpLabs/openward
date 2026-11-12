// Read-only capability checks and one ephemeral Secure Enclave key. No vault,
// password or existing Keychain item is read. Compile and ad-hoc sign before
// running; see spec/vault-session-v1.md. No key is persisted or exported.
import Foundation
import LocalAuthentication
import Security
import CryptoKit

let context = LAContext()
var policyError: NSError?
let available = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &policyError)
print("biometryAvailable=\(available) policyError=\(policyError?.code ?? 0)")
print("secureEnclaveAvailable=\(SecureEnclave.isAvailable)")
var error: Unmanaged<CFError>?
guard let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    [.privateKeyUsage, .biometryCurrentSet], &error) else {
  print("accessControlError=\(error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0)")
  exit(1)
}
let attributes: [String: Any] = [
  kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
  kSecAttrKeySizeInBits as String: 256,
  kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
  kSecPrivateKeyAttrs as String: [
    kSecAttrIsPermanent as String: false,
    kSecAttrAccessControl as String: control,
  ],
]
guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
  print("ephemeralEnclaveKeyError=\(error.map { CFErrorGetCode($0.takeRetainedValue()) } ?? 0)")
  exit(2)
}
let exported = SecKeyCopyExternalRepresentation(key, &error)
print("ephemeralPrivateKeyExportable=\(exported != nil)")
// A successful capability probe cannot prove a user completed Touch ID.
print("touchIdAuthentication=notPerformed")
exit(exported == nil ? 0 : 3)
