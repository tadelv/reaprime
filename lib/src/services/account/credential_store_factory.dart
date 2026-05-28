import 'dart:io' show Platform;

import 'package:reaprime/src/services/account/credential_store.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Factory that picks the right credential store for the platform.
///
/// On macOS, flutter_secure_storage hits errSecMissingEntitlement (-34018)
/// for Developer ID / debug builds because it sets kSecUseDataProtectionKeychain
/// internally. We fall back to SharedPreferences on macOS — the stored value is
/// already the encrypted cryptpw, so plaintext exposure risk is minimal.
///
/// iOS and Android use the Keychain / EncryptedSharedPreferences via
/// flutter_secure_storage.
CredentialStore createCredentialStore() {
  if (Platform.isMacOS) {
    return MacOSCredentialStore();
  }
  return SecureCredentialStore();
}

/// Stores credentials in macOS SharedPreferences.
///
/// SharedPreferences on macOS writes to the app's sandbox container which is
/// protected by the OS (no other user can read it). The stored value is the
/// encrypted cryptpw returned by login_test, not the user's plaintext password.
class MacOSCredentialStore implements CredentialStore {
  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> read({required String key}) async {
    final prefs = await _prefs;
    return prefs.getString(key);
  }

  @override
  Future<void> write({required String key, required String value}) async {
    final prefs = await _prefs;
    await prefs.setString(key, value);
  }

  @override
  Future<void> delete({required String key}) async {
    final prefs = await _prefs;
    await prefs.remove(key);
  }
}
