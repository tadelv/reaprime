import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:reaprime/src/services/account/credential_store.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:reaprime/src/services/account/encrypted_credential_store.dart';

/// Factory that picks the right credential store for the platform.
///
/// iOS and Android use flutter_secure_storage (Keychain /
/// EncryptedSharedPreferences).
///
/// macOS can't use the Keychain: flutter_secure_storage sets
/// kSecUseDataProtectionKeychain, and the Data Protection Keychain is
/// unavailable to Developer-ID / sideloaded builds, so every call returns
/// errSecMissingEntitlement (-34018). Instead we use an AES-256-GCM encrypted
/// file whose key is derived from the machine's hardware UUID — the same
/// pattern Slack/VS Code/Obsidian use on macOS.
Future<CredentialStore> createCredentialStore() async {
  if (Platform.isMacOS) {
    return _createMacOSStore();
  }
  return SecureCredentialStore();
}

// Authoritative bundle ID (see CLAUDE.md). Used as a fixed namespace in the
// key derivation; not a secret.
const _bundleId = 'net.tadel.reaprime';

Future<EncryptedCredentialStore> _createMacOSStore() async {
  final macInfo = await DeviceInfoPlugin().macOsInfo;

  // Machine-bound key: SHA-256(IOPlatformUUID || bundleID). Bound to the host
  // (a copied file won't decrypt elsewhere) but not to the binary signature
  // (survives auto-updates). systemGUID is the IOPlatformUUID.
  final guid = macInfo.systemGUID ?? 'unknown-machine';
  final keyBytes = sha256.convert(utf8.encode('$guid$_bundleId')).bytes;

  final dir = await getApplicationSupportDirectory();
  final path = p.join(dir.path, 'secure_storage_v1.dat');

  return EncryptedCredentialStore(
    keyBytes: keyBytes,
    blob: FileBlobStore(path),
  );
}
