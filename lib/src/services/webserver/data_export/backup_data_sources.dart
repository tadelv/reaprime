import 'package:reaprime/src/models/data/bean.dart';
import 'package:reaprime/src/models/data/grinder.dart';
import 'package:reaprime/src/models/data/shot_record.dart';
import 'package:reaprime/src/models/data/steam_record.dart';

/// A stable, bounded page of records for streaming export.
///
/// Implementations must return at most [limit] records, and an empty list
/// when no more records remain. Cursor parameters identify the last record
/// of the previous page so concurrent inserts/deletes cannot cause
/// duplicates or omissions (keyset paging).
typedef PageCursor<T> =
    Future<List<T>> Function(
      int limit, {
      DateTime? afterTimestamp,
      DateTime? afterCreatedAt,
      String? afterId,
    });

/// Bundle of DB-backed paging sources used by streaming export sections.
///
/// Keeps the storage service interfaces unchanged: the real DAO-backed page
/// functions are built once in `main.dart` where the `AppDatabase` is
/// available, and every test can inject its own instrumented paging seam.
/// Profile and KV paging closures are built inside `startWebServer` from the
/// profile controller and KV store respectively.
class BackupDataSources {
  /// Keyset-paged shot records (ordered by timestamp, id).
  final PageCursor<ShotRecord> pageShots;

  /// Keyset-paged steam records (ordered by timestamp, id).
  final PageCursor<SteamRecord> pageSteams;

  /// Keyset-paged beans (ordered by createdAt, id).
  final PageCursor<Bean> pageBeans;

  /// Keyset-paged grinders (ordered by createdAt, id).
  final PageCursor<Grinder> pageGrinders;

  const BackupDataSources({
    required this.pageShots,
    required this.pageSteams,
    required this.pageBeans,
    required this.pageGrinders,
  });
}
