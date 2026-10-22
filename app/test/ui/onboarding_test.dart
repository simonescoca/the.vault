// First access: the server check messages, and the approval code confirmed on the new device too.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:the_vault/src/app/app_controller.dart';
import 'package:the_vault/src/app/settings.dart';
import 'package:the_vault/src/core/account/identity.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';
import 'package:the_vault/src/ui/app.dart';

import 'harness.dart';

/// The app at its first access (Italian UI), talking to [client].
Future<AppController> pumpOnboarding(WidgetTester tester, VaultCrypto crypto, http.Client client) async {
  late AppController app;
  await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('tv-ui');
    final settings = AppSettings(File('${dir.path}/settings.json'))..language = 'it';
    app = AppController(
      crypto: crypto,
      secrets: MemorySecretStore(),
      platform: FakePlatform(),
      settings: settings,
      dataDir: dir.path,
      online: false,
      httpClient: client,
    );
    await app.init();
  });
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(TheVaultApp(app: app));
  await tester.pumpAndSettle();
  expect(app.phase, AppPhase.onboarding);
  await tester.tap(find.text('Inizia'));
  await tester.pumpAndSettle();
  return app;
}

/// The server and the device that approves.
class FakeServer {
  FakeServer(this.crypto)
      : vaultKey = crypto.newVaultKey(),
        approver = crypto.newBoxKeyPair(),
        nonce = crypto.randomBytes(32);

  final VaultCrypto crypto;
  final SecureKey vaultKey;
  final KeyPair approver;
  final Uint8List nonce;
  Uint8List? deviceKey;
  Uint8List? revealed;
  String state = 'pending';
  Map<String, String>? sealed;
  final calls = <String>[];

  void approve() {
    final s = crypto.sealVaultKey(
      vaultKey: vaultKey,
      userId: 'u1',
      approvalId: 'ap1',
      newDevicePublicKey: deviceKey!,
      approverSecretKey: approver.secretKey,
    );
    sealed = {'box': b64(s.box), 'boxNonce': b64(s.nonce)};
    state = 'approved';
  }

  String get code {
    final c = crypto.approvalCode(
      approvalId: 'ap1',
      newDevicePublicKey: deviceKey!,
      approverPublicKey: approver.publicKey,
      approverNonce: nonce,
      newDeviceNonce: revealed!,
    );
    return '${c.substring(0, 3)} ${c.substring(3)}';
  }

  Future<http.Response> handle(http.Request r) async {
    final call = '${r.method} ${r.url.path}';
    calls.add(call);
    http.Response json(Object j) => http.Response(jsonEncode(j), 200);
    switch (call) {
      case 'GET /v1/health':
        return json({'service': 'thevault'});
      case 'POST /v1/auth/otp/request':
        return json({});
      case 'POST /v1/auth/otp/verify':
        deviceKey = unb64(((jsonDecode(r.body) as Map)['device'] as Map)['publicKey'] as String);
        return json({'token': 'tok', 'deviceId': 'd2', 'userId': 'u1', 'status': 'pending'});
      case 'POST /v1/approvals':
        state = 'pending';
        revealed = null;
        sealed = null;
        return json({'approvalId': 'ap1'});
      case 'GET /v1/approvals/ap1':
        return json({
          'id': 'ap1',
          'state': state,
          if (state != 'pending') ...{'responderPublicKey': b64(approver.publicKey), 'responderNonce': b64(nonce)},
          ...?sealed,
        });
      case 'POST /v1/approvals/ap1/reveal':
        revealed = unb64((jsonDecode(r.body) as Map)['nonce'] as String);
        state = 'revealed';
        return http.Response('', 204);
      case 'DELETE /v1/approvals/ap1':
        state = 'cancelled';
        return http.Response('', 204);
      case 'GET /v1/me':
        return json({'vault': {'initialized': true, 'keyCheck': b64(crypto.keyCheck(vaultKey))}});
    }
    return http.Response('{"error":{"code":"not_found","message":"no such endpoint"}}', 404);
  }
}

void main() {
  late VaultCrypto crypto;
  setUpAll(() async => crypto = await VaultCrypto.init());

  testWidgets('server check: a stopped server behind Funnel is unreachable, not "not The Vault"', (tester) async {
    var answer = http.Response('', 502);
    await pumpOnboarding(tester, crypto, MockClient((_) async => answer));

    Future<void> check(http.Response r, Matcher message) async {
      answer = r;
      await tester.enterText(fieldWithHint('es. server.tail1234.ts.net'), 'vault.example.ts.net');
      await tester.tap(find.text('Continua'));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate((w) => w is Text && message.matches(w.data, {})), findsOneWidget,
          reason: '${r.statusCode} ${r.body}');
    }

    const unreachable = "Server non raggiungibile. Controlla l'indirizzo e che il server sia acceso.";
    const notVault = 'Questo non è un server The Vault.';
    await check(http.Response('', 502), equals(unreachable));
    await check(http.Response('<html><body>Service Unavailable</body></html>', 503), equals(unreachable));
    await check(http.Response('<!doctype html><title>Welcome to nginx</title>', 200), equals(notVault));
    await check(http.Response('{"status":"ok"}', 200), equals(notVault));
    await check(http.Response('<html>Not Found</html>', 404), equals(notVault));
    await check(http.Response('Client sent an HTTP request to an HTTPS server.', 400), equals(notVault));
    await check(http.Response('{"message":"no route"}', 404), equals(notVault));
    // Errors of The Vault itself are shown as they are.
    await check(http.Response('{"error":{"code":"internal","message":"errore interno"}}', 500), equals('Qualcosa è andato storto: errore interno'));
    await check(http.Response('{"error":{"code":"rate_limited","message":""},"retryAfter":30}', 429), equals('Troppi tentativi. Riprova tra 30 s.'));

    answer = http.Response('{"service":"thevault","version":"1.1.0"}', 200);
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    expect(find.text('La tua email'), findsOneWidget);
  });

  /// Server, email and code: up to the approval step.
  Future<AppController> toApproval(WidgetTester tester, Future<http.Response> Function(http.Request) handler) async {
    final app = await pumpOnboarding(tester, crypto, MockClient(handler));
    await tester.enterText(fieldWithHint('es. server.tail1234.ts.net'), 'vault.example.ts.net');
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();
    await tester.enterText(fieldWithHint('nome@esempio.it'), 'me@example.com');
    await tester.tap(find.text('Invia codice'));
    await tester.pumpAndSettle();
    tester.testTextInput.enterText('123456');
    await poll(tester);
    expect(find.text('Conferma questo dispositivo'), findsOneWidget);
    return app;
  }

  testWidgets('new device: the code is confirmed here too; "Non coincide" cancels the request', (tester) async {
    final server = FakeServer(crypto);
    final app = await toApproval(tester, server.handle);
    expect(find.text('In attesa di approvazione…'), findsOneWidget);

    // The other device answers: the code appears with the two choices.
    server.state = 'responded';
    await poll(tester);
    expect(find.text(server.code), findsOneWidget);
    expect(find.text("Controlla che sull'altro dispositivo compaia lo stesso codice, approva da lì e poi conferma qui."), findsOneWidget);
    await tester.tap(find.text('Non coincide'));
    await poll(tester);
    expect(find.text('I codici non coincidono: per sicurezza questo accesso è stato annullato.'), findsOneWidget);
    expect(server.calls, contains('DELETE /v1/approvals/ap1'));

    // A new request; this time the other device approves first, and nothing is kept until confirmed here.
    await tester.tap(find.text('Riprova'));
    await poll(tester);
    server.state = 'responded';
    await poll(tester);
    server.approve();
    await poll(tester);
    await poll(tester);
    expect(find.text('Il codice coincide'), findsOneWidget);
    expect(await app.secrets.readVaultKey(), isNull);

    await tester.tap(find.text('Il codice coincide'));
    await poll(tester);
    expect(find.text('Scegli un PIN di 6 cifre'), findsOneWidget);
    expect(await app.secrets.readVaultKey(), server.vaultKey.extractBytes());
    await tester.pumpAndSettle();
  });

  testWidgets('confirmed here first, then the other device approves: the PIN', (tester) async {
    final server = FakeServer(crypto);
    final app = await toApproval(tester, server.handle);
    server.state = 'responded';
    await poll(tester);
    await tester.tap(find.text('Il codice coincide'));
    await poll(tester);
    expect(find.text('In attesa di approvazione…'), findsOneWidget);
    server.approve();
    await poll(tester);
    await poll(tester);
    expect(find.text('Scegli un PIN di 6 cifre'), findsOneWidget);
    expect(await app.secrets.readVaultKey(), server.vaultKey.extractBytes());
    await tester.pumpAndSettle();
  });

  testWidgets('confirmed here, but the other device never answers: still a way out', (tester) async {
    final server = FakeServer(crypto);
    await toApproval(tester, server.handle);
    server.state = 'responded';
    await poll(tester);
    await tester.tap(find.text('Il codice coincide'));
    await poll(tester);
    expect(find.text('In attesa di approvazione…'), findsOneWidget);
    await tester.tap(find.text('Non ho altri dispositivi'));
    await poll(tester);
    expect(server.calls, contains('DELETE /v1/approvals/ap1'));
    expect(find.text('Codice di emergenza'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('emergency code refused because this device is no longer pending: signed out, back to the email', (tester) async {
    final server = FakeServer(crypto);
    final app = await toApproval(tester, (r) async => r.url.path == '/v1/recovery'
        ? http.Response('{"error":{"code":"forbidden","message":"not allowed for a device in status active"}}', 403)
        : server.handle(r));
    await tester.tap(find.text('Non ho altri dispositivi'));
    await poll(tester);
    await tester.enterText(find.byType(TextField), 'ABCD-EFGH-JKMN-PQRS-TVWX-YZ01');
    await tester.tap(find.text('Apri la cassaforte'));
    await poll(tester);
    expect(server.calls, contains('DELETE /v1/devices/self'));
    expect(find.text('La tua email'), findsOneWidget);
    expect(find.text("Questo dispositivo non è più collegato al tuo account: ricomincia dall'email."), findsOneWidget);
    expect(find.textContaining('not allowed'), findsNothing);
    expect(await app.secrets.readIdentity(), isNull);
    await tester.pumpAndSettle();
  });

  test('an interrupted first access is signed out on the server too at the next start', () async {
    final calls = <String>[];
    final dir = await Directory.systemTemp.createTemp('tv-ui');
    final secrets = MemorySecretStore();
    final kp = crypto.newBoxKeyPair();
    await secrets.writeIdentity(Identity(
      server: Uri.parse('https://vault.example.ts.net'),
      email: 'me@example.com',
      userId: 'u1',
      deviceId: 'd2',
      deviceName: 'PC',
      platform: 'windows',
      token: 'tok',
      devicePublicKey: kp.publicKey,
      deviceSecretKey: kp.secretKey.extractBytes(),
      status: 'pending', // e.g. closed while waiting for "Il codice coincide" after the other device approved
    ));
    final app = AppController(
      crypto: crypto,
      secrets: secrets,
      platform: FakePlatform(),
      settings: AppSettings(File('${dir.path}/settings.json')),
      dataDir: dir.path,
      online: false,
      httpClient: MockClient((r) async {
        calls.add('${r.method} ${r.url.path}');
        return http.Response('', 204);
      }),
    );
    await app.init();
    expect(app.phase, AppPhase.onboarding);
    expect(await secrets.readIdentity(), isNull);
    for (var i = 0; i < 50 && calls.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(calls, ['DELETE /v1/devices/self']);
    app.dispose();
    await dir.delete(recursive: true);
  });

  testWidgets('"Non ho altri dispositivi" after the other device approved: signed out, back to the email', (tester) async {
    final server = FakeServer(crypto);
    final app = await toApproval(tester, server.handle);
    server.state = 'responded';
    await poll(tester);
    server.approve();
    await poll(tester);
    await poll(tester);
    await tester.tap(find.text('Non ho altri dispositivi'));
    await poll(tester);
    expect(server.calls, contains('DELETE /v1/devices/self'));
    expect(find.text('La tua email'), findsOneWidget, reason: 'not the emergency code: this device is no longer pending');
    expect(await app.secrets.readVaultKey(), isNull);
    expect(await app.secrets.readIdentity(), isNull);
    await tester.pumpAndSettle();
  });

  testWidgets('this device is no longer known (401 at the start): said so, and start again from the email', (tester) async {
    final server = FakeServer(crypto);
    await toApproval(tester, (r) async => r.method == 'POST' && r.url.path == '/v1/approvals'
        ? http.Response('{"error":{"code":"device_unknown","message":"unknown device"}}', 401)
        : server.handle(r));
    expect(find.text("Questo dispositivo non è più collegato al tuo account: ricomincia dall'email."), findsOneWidget);
    expect(find.text('Riprova'), findsNothing);
    expect(find.text('Non ho altri dispositivi'), findsNothing);
    await tester.tap(find.text('Ricomincia'));
    await tester.pumpAndSettle();
    expect(find.text('La tua email'), findsOneWidget);
  });
}

/// Some steps show a spinner: pump the poll interval instead of settling.
Future<void> poll(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 600));
  }
}
