import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:the_vault/src/core/storage/local_db.dart';

void main() {
  Uint8List b(int v) => Uint8List.fromList([v]);

  test('pending changes overlay server records; queue keeps the original base revision', () {
    final db = LocalDb.memory();
    db.upsertRecord(RecordRow(id: 'a', rev: 5, data: b(1), deleted: false, blobs: const []));
    db.upsertRecord(RecordRow(id: 'gone', rev: 6, data: null, deleted: true, blobs: const []));
    expect(db.effective().keys, ['a']);

    db.putPending(id: 'a', op: 'put', data: b(2));
    db.putPending(id: 'new', op: 'put', data: b(3), blobs: ['x']);
    db.putPending(id: 'a', op: 'put', data: b(4)); // edited twice offline
    final q = db.pendingQueue();
    expect(q.map((p) => p.id), ['a', 'new'], reason: 'order of the first change');
    expect(q.first.baseRev, 5);
    expect(q.first.version, 2);
    expect(q.first.data, b(4));
    expect(q[1].baseRev, 0);
    final eff = db.effective();
    expect(eff['a']!.data, b(4));
    expect(eff['a']!.local, isTrue);
    expect(db.referencedBlobs(), {'x'});

    db.putPending(id: 'a', op: 'delete');
    expect(db.effective().containsKey('a'), isFalse);
  });

  test('acknowledge keeps a change made while the previous one was being sent', () {
    final db = LocalDb.memory();
    db.putPending(id: 'a', op: 'put', data: b(1));
    final sent = db.pendingQueue().single;
    db.putPending(id: 'a', op: 'put', data: b(2)); // user edits during the upload
    db.acknowledge(sent, 7);
    expect(db.record('a')!.rev, 7);
    expect(db.record('a')!.data, b(1));
    final still = db.pending('a')!;
    expect(still.baseRev, 7, reason: 'rebased on the acknowledged revision');
    expect(still.data, b(2));
    db.acknowledge(still, 8);
    expect(db.pending('a'), isNull);
    expect(db.pendingCount, 0);
  });

  test('meta, cursor, blobs, favicons and wipe', () {
    final db = LocalDb.memory();
    expect(db.cursor, 0);
    db.cursor = 42;
    expect(db.cursor, 42);
    db.setMeta('server', 'https://x');
    expect(db.meta('server'), 'https://x');
    db.setBlob('b1', 'local', 10);
    db.setBlob('b1', 'synced', 10);
    expect(db.blob('b1')!.state, 'synced');
    expect(db.blobsInState('synced').single.id, 'b1');
    db.setFavicon('9f2c', b(9), 1);
    expect(db.favicon('9f2c')!.data, b(9));
    db.wipe();
    expect(db.cursor, 0);
    expect(db.blob('b1'), isNull);
    expect(db.favicon('9f2c'), isNull);
  });
}
