import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [SyncOutbox])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.attachedDatabase);

  Future<void> enqueue(OutboxEntity entity, String entityUuid) => into(
    syncOutbox,
  ).insert(SyncOutboxCompanion.insert(entity: entity, entityUuid: entityUuid));

  /// Jumlah data yang belum dikonfirmasi server.
  Stream<int> watchPendingCount() {
    final count = syncOutbox.id.count();
    final query = selectOnly(syncOutbox)
      ..addColumns([count])
      ..where(syncOutbox.sentAt.isNull());
    return query.map((r) => r.read(count) ?? 0).watchSingle();
  }

  /// Antrian tertua dulu, untuk dikirim mesin sinkron (Tahap C).
  Future<List<OutboxRow>> pending({int limit = 50}) {
    return (select(syncOutbox)
          ..where((o) => o.sentAt.isNull())
          ..orderBy([(o) => OrderingTerm.asc(o.id)])
          ..limit(limit))
        .get();
  }

  Future<void> markSent(int id, DateTime at) =>
      (update(syncOutbox)..where((o) => o.id.equals(id))).write(
        SyncOutboxCompanion(sentAt: Value(at), lastError: const Value(null)),
      );

  Future<void> markFailed(int id, DateTime at, String error) => customUpdate(
    'UPDATE sync_outbox SET attempts = attempts + 1, '
    'last_attempt_at = ?, last_error = ? WHERE id = ?',
    variables: [
      Variable.withDateTime(at),
      Variable.withString(error),
      Variable.withInt(id),
    ],
    updates: {syncOutbox},
  );
}
