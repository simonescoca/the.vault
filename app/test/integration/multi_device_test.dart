// End-to-end: real server, several simulated devices, the real app logic.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:the_vault/src/app/app_controller.dart';
import 'package:the_vault/src/app/settings.dart';
import 'package:the_vault/src/core/account/account_service.dart';
import 'package:the_vault/src/core/account/identity.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/crypto/recovery_code.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/model/item_draft.dart';
import 'package:the_vault/src/core/session.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';
import 'package:the_vault/src/core/sync/sync_engine.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

import '../ui/harness.dart' show FakePlatform;
import 'server_harness.dart';

const email = 'me@example.com';

class Device {
  Device(this.name, this.platform, this.crypto)
      : secrets = MemorySecretStore(),
        dir = Directory.systemTemp.createTempSync('tv-$platform');

  final String name;
  final String platform;
  final VaultCrypto crypto;
  final MemorySecretStore secrets;
  final Directory dir;
  late final AccountService account = AccountService(crypto: crypto, secrets: secrets);
  Identity? identity;
  Session? session;

  Future<Identity> login(TestServer server) async {
    final url = await account.checkServer(server.url.toString());
    await account.requestCode(url, email, deviceName: name);
    return identity = await account.verifyCode(
        server: url, email: email, code: server.lastCode(), deviceName: name, platform: platform);
  }

  Session open(SecureKey vk, {bool realtime = true}) {
    final s = session = Session.open(identity: identity!, dataDir: dir.path, crypto: crypto);
    s.vault.unlock(vk);
    if (realtime) s.start();
    return s;
  }

  VaultController get vault => session!.vault;

  /// The real app on this device's data (identity and vault key already in its keychain), PIN 123456.
  Future<AppController> app() async {
    final a = AppController(
      crypto: crypto,
      secrets: secrets,
      platform: FakePlatform(),
      settings: AppSettings(File('${dir.path}/settings.json')),
      dataDir: dir.path,
    );
    await a.lock.setPin('123456');
    await a.init();
    return a;
  }

  Future<void> close() async {
    await session?.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

Future<void> eventually(bool Function() cond, {String what = 'condition', Duration timeout = const Duration(seconds: 15)}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) fail('timeout waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

Item newItem(String title, Map<String, String> rows, {bool hiddenLast = false}) {
  var n = 0;
  final d = ItemDraft.blank(const [], () => 'f${n++}')..title = title;
  rows.forEach((k, v) => d.addRow()
    ..key = k
    ..value = v);
  if (hiddenLast) d.fields.last.hidden = true;
  return (d.build(id: VaultController.newId(), now: DateTime.now()) as SaveOk).item;
}

void main() {
  late TestServer server;
  late VaultCrypto crypto;
  final devices = <Device>[];
  final apps = <AppController>[];

  setUpAll(() async {
    crypto = await VaultCrypto.init();
    server = await TestServer.start();
    ApprovalRequest.pollEvery = const Duration(milliseconds: 100);
    ApprovalResponse.pollEvery = const Duration(milliseconds: 100);
  });

  tearDownAll(() async {
    SyncEngine.unrecognizedRetry = const Duration(minutes: 10);
    for (final a in apps) {
      final s = a.session;
      a.session = null;
      await s?.close();
      a.dispose();
    }
    for (final d in devices) {
      await d.close();
    }
    await server.stop();
  });

  test('two devices, approval, real-time sync, conflicts, attachments, trash, recovery, revocation', () async {
    // ---------------------------------------------------------------- first device creates the vault
    final mac = Device('MacBook di Simone', 'macos', crypto);
    devices.add(mac);
    final macId = await mac.login(server);
    expect(macId.status, 'setup');
    final created = await mac.account.createVault(macId);
    final recovery = created.code;
    expect(macId.status, 'active');
    expect(await mac.secrets.readVaultKey(), isNotNull);
    mac.open(created.vaultKey);

    final netflix = newItem('Netflix', {'sito web': 'netflix.com', 'email': 'me@example.com', 'password': 'pw-1'}, hiddenLast: true);
    mac.vault.save(netflix);
    await mac.session!.sync.sync();
    expect(mac.session!.db.pendingCount, 0, reason: 'pushed to the server');

    // ---------------------------------------------------------------- second device needs approval
    final pc = Device('PC di casa', 'windows', crypto);
    devices.add(pc);
    final pcId = await pc.login(server);
    expect(pcId.status, 'pending');

    final requests = <ApprovalInfo>[];
    final sub = mac.session!.approvalRequests.listen(requests.add);
    final request = pc.account.requestApproval(pcId);
    final progress = <ApprovalProgress>[];
    request.progress.listen(progress.add);

    await eventually(() => requests.isNotEmpty, what: 'approval request on the Mac');
    expect(requests.single.deviceName, 'PC di casa');
    final response = ApprovalResponse(crypto, mac.session!.api, requests.single);
    final codeOnMac = await response.start();
    await eventually(() => progress.any((p) => p is ApprovalCode), what: 'code on the PC');
    final codeOnPc = progress.whereType<ApprovalCode>().single.code;
    expect(codeOnPc, codeOnMac, reason: 'both screens show the same 6 digits');
    await response.approve(vaultKey: mac.vault.vaultKey, userId: macId.userId);
    // Approved on the Mac, but the PC keeps the key only once the user confirmed the code there too.
    await Future<void>.delayed(ApprovalRequest.pollEvery * 5);
    expect(progress.any((p) => p is ApprovalGranted), isFalse);
    expect(await pc.secrets.readVaultKey(), isNull);
    await request.confirmCode();
    await eventually(() => progress.any((p) => p is ApprovalGranted), what: 'approval granted');
    await sub.cancel();
    expect(pcId.status, 'active');
    final pcKey = progress.whereType<ApprovalGranted>().single.vaultKey;
    expect(pcKey.extractBytes(), mac.vault.vaultKey.extractBytes());
    expect(server.mailLog, contains('Nuovo dispositivo collegato'));

    pc.open(pcKey);
    await eventually(() => pc.vault.byId(netflix.id) != null, what: 'Netflix on the PC');
    final onPc = pc.vault.byId(netflix.id)!;
    expect(onPc.fields.last.hidden, isTrue);
    expect(onPc.fields.last.value, 'pw-1');

    // ---------------------------------------------------------------- real-time: Mac → PC in a moment
    final amazon = newItem('Amazon', {'email': 'me@example.com'});
    final sw = Stopwatch()..start();
    mac.vault.save(amazon);
    await eventually(() => pc.vault.byId(amazon.id) != null, what: 'Amazon on the PC');
    expect(sw.elapsed, lessThan(const Duration(seconds: 5)));

    // ---------------------------------------------------------------- favorite + eye toggles sync
    pc.vault.setFavorite(amazon.id, true);
    await eventually(() => mac.vault.byId(amazon.id)!.favorite, what: 'favorite on the Mac');
    expect(mac.vault.list(Section.favorites).map((i) => i.id), [amazon.id]);

    // ---------------------------------------------------------------- real conflict → copy, nothing lost
    await pc.session!.realtime.stop(); // the PC goes "offline"
    mac.vault.save(mac.vault.byId(netflix.id)!.copyWith(title: 'Netflix (Mac)'));
    await mac.session!.sync.sync();
    pc.vault.save(pc.vault.byId(netflix.id)!.copyWith(title: 'Netflix (PC)'));
    await pc.session!.sync.sync(); // conflict resolved here
    await pc.session!.sync.sync();
    final titlesPc = pc.vault.list(Section.all).map((i) => i.title).toSet();
    expect(titlesPc, containsAll(['Netflix (Mac)', 'Netflix (PC) (conflitto)']));
    await mac.session!.sync.sync();
    expect(mac.vault.list(Section.all).map((i) => i.title).toSet(), containsAll(['Netflix (Mac)', 'Netflix (PC) (conflitto)']));

    // ---------------------------------------------------------------- flags-only conflict → merged, no copy
    final before = pc.vault.list(Section.all).length;
    mac.vault.setFavorite(netflix.id, true);
    await mac.session!.sync.sync();
    pc.vault.save(pc.vault.byId(netflix.id)!.copyWith(description: 'Account di famiglia'));
    await pc.session!.sync.sync();
    await pc.session!.sync.sync();
    final merged = pc.vault.byId(netflix.id)!;
    expect(merged.favorite, isTrue, reason: "the Mac's star is kept");
    expect(merged.description, 'Account di famiglia', reason: "the PC's edit is kept");
    expect(pc.vault.list(Section.all).length, before, reason: 'no conflict copy');
    pc.session!.realtime.start();

    // ---------------------------------------------------------------- attachments
    final src = File('${mac.dir.path}/contratto.pdf')..writeAsBytesSync(List<int>.generate(300000, (i) => i % 251));
    final att = await mac.vault.addAttachment(src);
    expect(att.mime, 'application/pdf');
    mac.vault.save(mac.vault.byId(amazon.id)!.copyWith(files: [att]));
    await mac.session!.sync.sync();
    expect(mac.session!.db.blob(att.id)!.state, 'synced');
    await eventually(() => pc.vault.byId(amazon.id)!.files.isNotEmpty, what: 'attachment metadata on the PC');
    final exported = await pc.vault.exportAttachment(pc.vault.byId(amazon.id)!.files.single, '${pc.dir.path}/open');
    expect(exported.readAsBytesSync(), src.readAsBytesSync());
    expect(exported.path, endsWith('contratto.pdf'));

    // ---------------------------------------------------------------- trash, restore, delete forever
    mac.vault.moveToTrash(amazon.id);
    await eventually(() => pc.vault.byId(amazon.id)?.inTrash == true, what: 'trash on the PC');
    expect(pc.vault.list(Section.all).any((i) => i.id == amazon.id), isFalse);
    expect(pc.vault.list(Section.trash).map((i) => i.id), [amazon.id]);
    pc.vault.restore(amazon.id);
    await eventually(() => mac.vault.byId(amazon.id)?.inTrash == false, what: 'restore on the Mac');
    mac.vault.moveToTrash(amazon.id);
    await mac.session!.sync.sync();
    mac.vault.deleteForever(amazon.id);
    await mac.session!.sync.sync();
    await eventually(() => pc.vault.byId(amazon.id) == null, what: 'permanent delete on the PC');

    // ---------------------------------------------------------------- third device with the emergency code
    final laptop = Device('Laptop nuovo', 'macos', crypto);
    devices.add(laptop);
    final lapId = await laptop.login(server);
    expect(lapId.status, 'pending');
    final wrong = RecoveryCode.random(crypto.randomBytes(15));
    await expectLater(laptop.account.useRecoveryCode(lapId, wrong), throwsA(isA<CryptoException>()));
    final lapKey = await laptop.account.useRecoveryCode(lapId, RecoveryCode.tryParse(recovery.formatted)!);
    expect(lapId.status, 'active');
    laptop.open(lapKey);
    await eventually(() => laptop.vault.list(Section.all).any((i) => i.title == 'Netflix (Mac)'), what: 'data on the laptop');

    // ---------------------------------------------------------------- revocation
    var revoked = false;
    var unrecognized = false;
    laptop.session!.onRevoked = () => revoked = true;
    laptop.session!.onUnrecognized = () => unrecognized = true;
    final devs = await mac.session!.api.devices();
    expect(devs.map((d) => d.name), containsAll(['MacBook di Simone', 'PC di casa', 'Laptop nuovo']));
    await mac.session!.api.revokeDevice(lapId.deviceId);
    await eventually(() => revoked, what: 'laptop told it was revoked');
    // 401, so that apps up to 1.1.0 (which wipe on any 401) keep wiping; the code tells it from an unknown token.
    final isRevoked = isA<ApiException>().having((e) => e.status, 'status', 401).having((e) => e.code, 'code', 'device_revoked');
    await expectLater(laptop.session!.api.me(), throwsA(isRevoked));
    // Without the real-time event (e.g. offline at that moment) the next sync finds out.
    await laptop.session!.realtime.stop();
    revoked = false;
    await laptop.session!.sync.sync();
    expect(revoked, isTrue);
    expect(unrecognized, isFalse);

    // ---------------------------------------------------------------- the real app: revoked → everything deleted
    final tablet = Device('Tablet', 'linux', crypto);
    devices.add(tablet);
    final tabId = await tablet.login(server);
    await tablet.account.useRecoveryCode(tabId, RecoveryCode.tryParse(recovery.formatted)!);
    final tabApp = await tablet.app();
    apps.add(tabApp);
    final tabNotices = <AppNotice>[];
    tabApp.notices.listen(tabNotices.add);
    expect(tabApp.phase, AppPhase.locked);
    await tabApp.unlockWithPin('123456');
    await eventually(() => tabApp.session!.vault.list(Section.all).isNotEmpty, what: 'data on the tablet');
    final tabSession = tabApp.session!;
    await tabSession.realtime.stop(); // no real-time event: the 401 device_revoked alone is enough
    await mac.session!.api.revokeDevice(tabId.deviceId);
    await Future.wait([tabSession.sync.sync(), tabSession.sync.sync()]);
    tabSession.onRevoked?.call(); // the real-time event racing the sync: still one wipe
    await eventually(() => tabApp.phase == AppPhase.onboarding, what: 'tablet wiped');
    await eventually(() => tabNotices.contains(AppNotice.deviceRevoked), what: 'revoked notice');
    tabSession.onRevoked?.call(); // too late: ignored
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(tabNotices, [AppNotice.deviceRevoked]);
    expect(await tablet.secrets.readVaultKey(), isNull);
    expect(await tablet.secrets.readIdentity(), isNull);
    expect(File('${tablet.dir.path}/vault.db').existsSync(), isFalse);

    // ---------------------------------------------------------------- the real app: unknown token → nothing deleted
    final desk = Device('Desktop', 'linux', crypto);
    devices.add(desk);
    final deskId = await desk.login(server);
    final deskKey = await desk.account.useRecoveryCode(deskId, RecoveryCode.tryParse(recovery.formatted)!);
    final ds = desk.open(deskKey, realtime: false);
    await ds.sync.sync();
    expect(ds.vault.list(Section.all), isNotEmpty);
    await ds.close();
    desk.session = null;
    // The server no longer knows the token (e.g. its data was reset): simulated with a token it never issued.
    final unknownToken = b64(crypto.randomBytes(32));
    await desk.secrets.writeIdentity(Identity.fromJson({...deskId.toJson(), 'token': unknownToken}));
    final deskApp = await desk.app();
    apps.add(deskApp);
    final deskNotices = <AppNotice>[];
    deskApp.notices.listen(deskNotices.add);
    final dsess = deskApp.session!;
    await eventually(() => dsess.sync.unrecognized, what: '401 on the desktop');
    expect(deskApp.phase, AppPhase.locked, reason: 'not wiped');
    expect(deskNotices, isEmpty, reason: 'told once unlocked, when the data can be exported');

    // The server knows the device by the token again (e.g. the right backup was restored): the real-time channel
    // reconnects (it would by itself, within its slow retry after a refusal).
    Future<void> serverKnows(String token) async {
      dsess.api.token = token;
      dsess.realtime.token = token;
      await dsess.realtime.stop();
      dsess.realtime.start();
    }

    // Recognized again before the user unlocks, seen by a request (REST): syncing resumes, the real-time channel
    // refused at start comes back at once (not after its 10-minute wait), and the warning is no longer due.
    await eventually(() => dsess.realtime.refused, what: 'real-time channel refused');
    dsess.api.token = deskId.token;
    dsess.realtime.token = deskId.token;
    await dsess.sync.sync(force: true);
    expect(dsess.sync.unrecognized, isFalse);
    await eventually(() => dsess.realtime.connected.value, what: 'real-time channel back at once');
    await deskApp.unlockWithPin('123456');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(deskNotices, isEmpty, reason: 'recognized again meanwhile: no warning');

    // While unlocked the server forgets it again: warned once, nothing deleted, new edits kept.
    dsess.api.token = unknownToken;
    await dsess.sync.sync();
    await eventually(() => deskNotices.isNotEmpty, what: 'unrecognized notice');
    expect(dsess.vault.list(Section.all), isNotEmpty, reason: 'the data is still here');
    final later = newItem('Scritta dopo', {'nota': 'non si perde'});
    dsess.vault.save(later);
    await dsess.sync.sync(force: true);
    await dsess.sync.sync(force: true);
    expect(deskNotices, [AppNotice.deviceUnrecognized], reason: 'not repeated at every retry');
    expect(deskApp.phase, AppPhase.unlocked);
    expect(dsess.db.pendingCount, 1, reason: 'the new entry waits, it is not lost');
    expect(await desk.secrets.readVaultKey(), isNotNull);
    expect(File('${desk.dir.path}/vault.db').existsSync(), isTrue);

    // Known again, well within the 10-minute pause after the 401: the real-time channel connects and the edit goes out.
    expect(SyncEngine.unrecognizedRetry, const Duration(minutes: 10));
    await serverKnows(deskId.token);
    await eventually(() => dsess.db.pendingCount == 0, what: 'edit pushed once recognized');
    await eventually(() => mac.vault.byId(later.id) != null, what: 'the edit on the Mac');
    expect(dsess.sync.unrecognized, isFalse);
    expect(deskNotices, [AppNotice.deviceUnrecognized]);

    // ---------------------------------------------------------------- a stolen email is not enough
    final intruder = Device('Intruso', 'linux', crypto);
    devices.add(intruder);
    final intrId = await intruder.login(server);
    expect(intrId.status, 'pending');
    await expectLater(intruder.session?.api.records(0) ?? ApiClient(base: intrId.server, token: intrId.token).records(0),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
  });
}
