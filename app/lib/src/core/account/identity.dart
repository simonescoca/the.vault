import 'dart:convert';
import 'dart:typed_data';

import '../api/api_client.dart';
import '../storage/secret_store.dart';

/// Who this device is: kept in the OS keychain.
class Identity {
  Identity({
    required this.server,
    required this.email,
    required this.userId,
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    required this.token,
    required this.devicePublicKey,
    required this.deviceSecretKey,
    required this.status,
  });

  final Uri server;
  final String email;
  final String userId;
  final String deviceId;
  String deviceName;
  final String platform;
  final String token;
  final Uint8List devicePublicKey;
  final Uint8List deviceSecretKey;

  /// setup | pending | active
  String status;

  bool get isActive => status == 'active';

  Map<String, dynamic> toJson() => {
        'server': server.toString(),
        'email': email,
        'userId': userId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'platform': platform,
        'token': token,
        'pk': b64(devicePublicKey),
        'sk': b64(deviceSecretKey),
        'status': status,
      };

  factory Identity.fromJson(Map<String, dynamic> j) => Identity(
        server: Uri.parse(j['server'] as String),
        email: j['email'] as String,
        userId: j['userId'] as String,
        deviceId: j['deviceId'] as String,
        deviceName: j['deviceName'] as String,
        platform: j['platform'] as String,
        token: j['token'] as String,
        devicePublicKey: unb64(j['pk'] as String),
        deviceSecretKey: unb64(j['sk'] as String),
        status: j['status'] as String,
      );
}

/// Keys used in the secret store.
class SecretKeys {
  static const identity = 'thevault.identity';
  static const vaultKey = 'thevault.vaultKey';
  static const pinHash = 'thevault.pinHash';
  static const pinFails = 'thevault.pinFails';
  static const pinLockedUntil = 'thevault.pinLockedUntil';
  static const biometrics = 'thevault.biometrics';
}

extension IdentityStore on SecretStore {
  Future<Identity?> readIdentity() async {
    final s = await read(SecretKeys.identity);
    if (s == null) return null;
    try {
      return Identity.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeIdentity(Identity id) => write(SecretKeys.identity, jsonEncode(id.toJson()));

  Future<Uint8List?> readVaultKey() async {
    final s = await read(SecretKeys.vaultKey);
    return s == null ? null : unb64(s);
  }

  Future<void> writeVaultKey(Uint8List key) => write(SecretKeys.vaultKey, b64(key));
}
