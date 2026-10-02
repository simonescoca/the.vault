// Secrets of this device (vault key, device key, token, PIN hash) live in the OS keychain:
// macOS Keychain, Windows Credential Locker/DPAPI. Tests use the in-memory store.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<void> deleteAll() async => values.clear();
}

class OsSecretStore implements SecretStore {
  OsSecretStore()
      : _storage = const FlutterSecureStorage(
          // Without an Apple Developer signature the app cannot use the "data protection" keychain,
          // so it uses the classic login keychain (docs/SECURITY.md §9).
          mOptions: MacOsOptions(usesDataProtectionKeychain: false, accountName: 'The Vault'),
        );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Development-only store for Linux (no keyring in the test environment). Not used on macOS/Windows.
class FileSecretStore implements SecretStore {
  FileSecretStore(this.path);
  final String path;

  Map<String, String> _load() {
    final f = File(path);
    if (!f.existsSync()) return {};
    return Map<String, String>.from(jsonDecode(f.readAsStringSync()) as Map);
  }

  void _save(Map<String, String> m) {
    final f = File(path)..createSync(recursive: true);
    f.writeAsStringSync(jsonEncode(m));
  }

  @override
  Future<String?> read(String key) async => _load()[key];

  @override
  Future<void> write(String key, String value) async => _save(_load()..[key] = value);

  @override
  Future<void> delete(String key) async => _save(_load()..remove(key));

  @override
  Future<void> deleteAll() async {
    final f = File(path);
    if (f.existsSync()) f.deleteSync();
  }
}
