// HTTP client for the server API (docs/PROTOCOL.md).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../crypto/vault_crypto.dart';
import '../storage/local_db.dart';

/// The server answered with an error.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.body = const {}]);
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic> body;

  int? get retryAfter => (body['retryAfter'] as num?)?.toInt();

  @override
  String toString() => 'ApiException($status $code: $message)';
}

/// The server could not be reached.
class NetworkException implements Exception {
  NetworkException(this.cause);
  final Object cause;
  @override
  String toString() => 'NetworkException($cause)';
}

/// A write was refused because the record changed on the server.
class ConflictException implements Exception {
  ConflictException(this.current);
  final RecordRow current;
}

String b64(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

Uint8List unb64(String s) {
  var t = s.replaceAll('-', '+').replaceAll('_', '/');
  while (t.length % 4 != 0) {
    t += '=';
  }
  return base64.decode(t);
}

class VerifyResult {
  VerifyResult({required this.token, required this.deviceId, required this.userId, required this.status});
  final String token;
  final String deviceId;
  final String userId;
  final String status;
}

class DeviceInfo {
  DeviceInfo({
    required this.id,
    required this.name,
    required this.platform,
    required this.status,
    required this.createdAt,
    required this.lastSeenAt,
    required this.current,
  });
  final String id;
  final String name;
  final String platform;
  final String status;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final bool current;

  factory DeviceInfo.fromJson(Map<String, dynamic> j) => DeviceInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        platform: j['platform'] as String,
        status: j['status'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch((j['createdAt'] as num).toInt()),
        lastSeenAt: DateTime.fromMillisecondsSinceEpoch((j['lastSeenAt'] as num).toInt()),
        current: j['current'] == true,
      );
}

class ApprovalInfo {
  ApprovalInfo(this.json);
  final Map<String, dynamic> json;

  String get id => json['id'] as String;
  String get state => json['state'] as String;
  Uint8List get commitment => unb64(json['commitment'] as String);
  Map<String, dynamic>? get _device => json['device'] as Map<String, dynamic>?;
  String get deviceId => _device?['id'] as String? ?? '';
  String get deviceName => _device?['name'] as String? ?? '';
  String get devicePlatform => _device?['platform'] as String? ?? '';
  Uint8List? get devicePublicKey => _device?['publicKey'] == null ? null : unb64(_device!['publicKey'] as String);
  Uint8List? _opt(String k) => json[k] == null ? null : unb64(json[k] as String);
  Uint8List? get responderPublicKey => _opt('responderPublicKey');
  Uint8List? get responderNonce => _opt('responderNonce');
  Uint8List? get revealedNonce => _opt('revealedNonce');
  Uint8List? get box => _opt('box');
  Uint8List? get boxNonce => _opt('boxNonce');
  String? get responderDeviceId => json['responderDeviceId'] as String?;
}

class RecordsPage {
  RecordsPage(this.records, this.latest, this.more);
  final List<RecordRow> records;
  final int latest;
  final bool more;
}

class ApiClient {
  ApiClient({required this.base, this.token, http.Client? client, this.locale = 'it', this.timeout = const Duration(seconds: 30)})
      : _http = client ?? http.Client();

  Uri base;
  String? token;
  String locale;
  final Duration timeout;
  final http.Client _http;

  void close() => _http.close();

  /// "mac-mini.tail123.ts.net" → https://mac-mini.tail123.ts.net. Plain http is only accepted for
  /// local addresses (development, home network).
  static Uri? normalizeServer(String input) {
    var s = input.trim();
    if (s.isEmpty || s.contains(' ')) return null;
    if (!s.contains('://')) s = 'https://$s';
    final u = Uri.tryParse(s);
    if (u == null || u.host.isEmpty) return null;
    if (u.scheme == 'http' && !_isLocal(u.host)) return null;
    if (u.scheme != 'http' && u.scheme != 'https') return null;
    return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null);
  }

  static bool _isLocal(String host) {
    if (host == 'localhost') return true;
    final ip = InternetAddress.tryParse(host);
    if (ip == null) return host.endsWith('.local');
    if (ip.isLoopback || ip.isLinkLocal) return true;
    final b = ip.rawAddress;
    return ip.type == InternetAddressType.IPv4 &&
        (b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] < 32) || (b[0] == 192 && b[1] == 168));
  }

  Uri _u(String path, [Map<String, String>? q]) => base.replace(path: path, queryParameters: q);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept-Language': locale,
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Map<String, dynamic>> _send(String method, String path, {Object? body, Map<String, String>? query}) async {
    final req = http.Request(method, _u(path, query))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final http.Response resp;
    try {
      resp = await http.Response.fromStream(await _http.send(req).timeout(timeout)).timeout(timeout);
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on SocketException catch (e) {
      throw NetworkException(e);
    } on HandshakeException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    }
    Map<String, dynamic> json = const {};
    if (resp.body.isNotEmpty) {
      try {
        json = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
      } catch (_) {
        throw ApiException(resp.statusCode, 'bad_response', 'unexpected response from the server');
      }
    }
    if (resp.statusCode >= 400) {
      final e = json['error'] as Map<String, dynamic>? ?? const {};
      throw ApiException(resp.statusCode, e['code'] as String? ?? 'error', e['message'] as String? ?? '', json);
    }
    return json;
  }

  // ------------------------------------------------------------------ login

  Future<Map<String, dynamic>> health() async {
    final h = await _send('GET', '/v1/health');
    if (h['service'] != 'thevault') throw ApiException(200, 'not_thevault', 'not a The Vault server');
    return h;
  }

  Future<void> requestCode(String email, {String? deviceName}) =>
      _send('POST', '/v1/auth/otp/request', body: {'email': email, 'locale': locale, 'deviceName': ?deviceName});

  Future<VerifyResult> verifyCode({
    required String email,
    required String code,
    required String deviceName,
    required String platform,
    required Uint8List publicKey,
  }) async {
    final j = await _send('POST', '/v1/auth/otp/verify', body: {
      'email': email,
      'code': code,
      'device': {'name': deviceName, 'platform': platform, 'publicKey': b64(publicKey)},
    });
    return VerifyResult(
      token: j['token'] as String,
      deviceId: j['deviceId'] as String,
      userId: j['userId'] as String,
      status: j['status'] as String,
    );
  }

  Future<Map<String, dynamic>> me() => _send('GET', '/v1/me');

  Future<void> initVault({required Uint8List keyCheck, required RecoveryBundle recovery, required Uint8List recoveryAuth}) =>
      _send('POST', '/v1/vault/init', body: {
        'keyCheck': b64(keyCheck),
        'recovery': _recoveryJson(recovery),
        'recoveryAuth': b64(recoveryAuth),
      });

  Map<String, dynamic> _recoveryJson(RecoveryBundle r) =>
      {'salt': b64(r.salt), 'opsLimit': r.opsLimit, 'memLimit': r.memLimit, 'wrap': b64(r.wrap)};

  // --------------------------------------------------------------- devices

  Future<List<DeviceInfo>> devices() async {
    final j = await _send('GET', '/v1/devices');
    return [for (final d in j['devices'] as List) DeviceInfo.fromJson(Map<String, dynamic>.from(d as Map))];
  }

  Future<void> renameSelf(String name) => _send('PATCH', '/v1/devices/self', body: {'name': name});
  Future<void> signOut() => _send('DELETE', '/v1/devices/self');
  Future<void> revokeDevice(String id) => _send('DELETE', '/v1/devices/$id');

  // ------------------------------------------------------------- approvals

  Future<String> createApproval(Uint8List commitment) async =>
      (await _send('POST', '/v1/approvals', body: {'commitment': b64(commitment)}))['approvalId'] as String;

  Future<ApprovalInfo> approval(String id) async => ApprovalInfo(await _send('GET', '/v1/approvals/$id'));

  Future<List<ApprovalInfo>> openApprovals() async {
    final j = await _send('GET', '/v1/approvals');
    return [for (final a in j['approvals'] as List) ApprovalInfo(Map<String, dynamic>.from(a as Map))];
  }

  Future<void> revealApproval(String id, Uint8List nonce) =>
      _send('POST', '/v1/approvals/$id/reveal', body: {'nonce': b64(nonce)});

  Future<void> cancelApproval(String id) => _send('DELETE', '/v1/approvals/$id');

  Future<ApprovalInfo> respondApproval(String id, Uint8List publicKey, Uint8List nonce) async =>
      ApprovalInfo(await _send('POST', '/v1/approvals/$id/respond', body: {'publicKey': b64(publicKey), 'nonce': b64(nonce)}));

  Future<void> approveApproval(String id, Uint8List box, Uint8List boxNonce) =>
      _send('POST', '/v1/approvals/$id/approve', body: {'box': b64(box), 'boxNonce': b64(boxNonce)});

  Future<void> rejectApproval(String id) => _send('POST', '/v1/approvals/$id/reject');

  // -------------------------------------------------------------- recovery

  Future<RecoveryBundle> recovery() async {
    final j = await _send('GET', '/v1/recovery');
    return RecoveryBundle(
      salt: unb64(j['salt'] as String),
      opsLimit: (j['opsLimit'] as num).toInt(),
      memLimit: (j['memLimit'] as num).toInt(),
      wrap: unb64(j['wrap'] as String),
    );
  }

  Future<void> activateRecovery(Uint8List authKey) =>
      _send('POST', '/v1/recovery/activate', body: {'recoveryAuth': b64(authKey)});

  Future<void> replaceRecovery(RecoveryBundle r, Uint8List authKey) =>
      _send('PUT', '/v1/recovery', body: {'recovery': _recoveryJson(r), 'recoveryAuth': b64(authKey)});

  // --------------------------------------------------------------- records

  static RecordRow _record(Map<String, dynamic> j) => RecordRow(
        id: j['id'] as String,
        rev: (j['rev'] as num).toInt(),
        data: j['data'] == null ? null : unb64(j['data'] as String),
        deleted: j['deleted'] == true,
        blobs: [for (final b in (j['blobs'] as List? ?? const [])) b as String],
      );

  Future<RecordsPage> records(int since, {int limit = 500}) async {
    final j = await _send('GET', '/v1/records', query: {'since': '$since', 'limit': '$limit'});
    return RecordsPage(
      [for (final r in j['records'] as List) _record(Map<String, dynamic>.from(r as Map))],
      (j['latest'] as num).toInt(),
      j['more'] == true,
    );
  }

  Future<int> putRecord(String id, int baseRev, Uint8List data, List<String> blobs) async {
    try {
      final j = await _send('PUT', '/v1/records/$id', body: {'baseRev': baseRev, 'data': b64(data), 'blobs': blobs});
      return (j['rev'] as num).toInt();
    } on ApiException catch (e) {
      if (e.status == 409 && e.body['current'] != null) {
        throw ConflictException(_record(Map<String, dynamic>.from(e.body['current'] as Map)));
      }
      rethrow;
    }
  }

  Future<int> deleteRecord(String id, int baseRev) async {
    try {
      final j = await _send('DELETE', '/v1/records/$id', query: {'baseRev': '$baseRev'});
      return (j['rev'] as num).toInt();
    } on ApiException catch (e) {
      if (e.status == 409 && e.body['current'] != null) {
        throw ConflictException(_record(Map<String, dynamic>.from(e.body['current'] as Map)));
      }
      rethrow;
    }
  }

  // ----------------------------------------------------------------- blobs

  /// Starts (or resumes) an upload. Returns the part size, the parts already on the server and
  /// whether the blob is already complete.
  Future<({int partSize, Set<int> received, bool complete})> startBlob(String id, int size) async {
    final j = await _send('POST', '/v1/blobs/$id', body: {'size': size});
    return (
      partSize: (j['partSize'] as num).toInt(),
      received: {for (final n in (j['receivedParts'] as List? ?? const [])) (n as num).toInt()},
      complete: j['complete'] == true,
    );
  }

  Future<void> putBlobPart(String id, int n, Uint8List bytes) async {
    final req = http.Request('PUT', _u('/v1/blobs/$id/parts/$n'))
      ..headers.addAll({..._headers, 'Content-Type': 'application/octet-stream'})
      ..bodyBytes = bytes;
    try {
      final resp = await http.Response.fromStream(await _http.send(req).timeout(timeout * 4));
      if (resp.statusCode != 204) {
        Map<String, dynamic> j = const {};
        try {
          j = Map<String, dynamic>.from(jsonDecode(resp.body) as Map);
        } catch (_) {}
        final e = j['error'] as Map<String, dynamic>? ?? const {};
        throw ApiException(resp.statusCode, e['code'] as String? ?? 'error', e['message'] as String? ?? '', j);
      }
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on SocketException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    }
  }

  Future<void> completeBlob(String id, int parts, String sha256Hex) =>
      _send('POST', '/v1/blobs/$id/complete', body: {'parts': parts, 'sha256': sha256Hex});

  /// Downloads a blob into [sink], starting at byte [from] (resume). Returns the ETag (SHA-256 of the blob).
  Future<String?> downloadBlob(String id, IOSink sink, {int from = 0}) async {
    final req = http.Request('GET', _u('/v1/blobs/$id'))..headers.addAll(_headers);
    if (from > 0) req.headers['Range'] = 'bytes=$from-';
    try {
      final resp = await _http.send(req).timeout(timeout);
      if (resp.statusCode != 200 && resp.statusCode != 206) {
        final body = await resp.stream.bytesToString();
        Map<String, dynamic> j = const {};
        try {
          j = Map<String, dynamic>.from(jsonDecode(body) as Map);
        } catch (_) {}
        final e = j['error'] as Map<String, dynamic>? ?? const {};
        throw ApiException(resp.statusCode, e['code'] as String? ?? 'error', e['message'] as String? ?? '', j);
      }
      if (from > 0 && resp.statusCode == 200) {
        throw ApiException(200, 'range_ignored', 'the server ignored the range request');
      }
      await sink.addStream(resp.stream.timeout(const Duration(minutes: 2)));
      return resp.headers['etag']?.replaceAll('"', '');
    } on TimeoutException catch (e) {
      throw NetworkException(e);
    } on SocketException catch (e) {
      throw NetworkException(e);
    } on http.ClientException catch (e) {
      throw NetworkException(e);
    }
  }

  // ------------------------------------------------------------- realtime

  Uri get wsUri => base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/v1/ws');
}
