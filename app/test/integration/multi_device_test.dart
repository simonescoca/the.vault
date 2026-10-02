// End-to-end: real server, several simulated devices, the real app logic.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sodium/sodium_sumo.dart';
import 'package:the_vault/src/core/account/account_service.dart';
import 'package:the_vault/src/core/account/identity.dart';
import 'package:the_vault/src/core/api/api_client.dart';
import 'package:the_vault/src/core/crypto/recovery_code.dart';
import 'package:the_vault/src/core/crypto/vault_crypto.dart';
import 'package:the_vault/src/core/model/item.dart';
import 'package:the_vault/src/core/model/item_draft.dart';
import 'package:the_vault/src/core/session.dart';
import 'package:the_vault/src/core/storage/secret_store.dart';
import 'package:the_vault/src/core/vault/vault_controller.dart';

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

  setUpAll(() async {
    crypto = await VaultCrypto.init();
    server = await TestServer.start();
    ApprovalRequest.pollEvery = const Duration(milliseconds: 100);
    ApprovalResponse.pollEvery = const Duration(milliseconds: 100);
  });

  tearDownAll(() async {
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
    laptop.session!.onRevoked = () => revoked = true;
    final devs = await mac.session!.api.devices();
    expect(devs.map((d) => d.name), containsAll(['MacBook di Simone', 'PC di casa', 'Laptop nuovo']));
    await mac.session!.api.revokeDevice(lapId.deviceId);
    await eventually(() => revoked, what: 'laptop told it was revoked');
    await expectLater(laptop.session!.api.me(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)));

    // ---------------------------------------------------------------- a stolen email is not enough
    final intruder = Device('Intruso', 'linux', crypto);
    devices.add(intruder);
    final intrId = await intruder.login(server);
    expect(intrId.status, 'pending');
    await expectLater(intruder.session?.api.records(0) ?? ApiClient(base: intrId.server, token: intrId.token).records(0),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)));
  });
}
