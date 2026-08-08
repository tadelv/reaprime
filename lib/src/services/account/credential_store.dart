import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';

/// Flutter Secure Storage backed credential store.
/// Uses iOS Keychain, Android EncryptedSharedPreferences, macOS Keychain,
/// and Linux libsecret.
class SecureCredentialStore implements CredentialStore {
  final FlutterSecureStorage _storage;

  SecureCredentialStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // v10 changed the default Android ciphers (encryptedSharedPreferences
            // deprecated). Auto-migrate any creds written by v9 so existing
            // logins survive the upgrade instead of silently failing to read.
            aOptions: AndroidOptions(migrateOnAlgorithmChange: true),
          );

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);
}
