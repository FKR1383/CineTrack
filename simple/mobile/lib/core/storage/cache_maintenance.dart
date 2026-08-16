import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'local_database.dart';

class CacheMaintenanceResult {
  const CacheMaintenanceResult({required this.apiEntries, required this.mediaEntries});
  final int apiEntries;
  final int mediaEntries;
}

class CacheMaintenanceService {
  CacheMaintenanceService(this.localDatabase);
  final LocalDatabase localDatabase;

  Future<CacheMaintenanceResult> clearProviderCacheSafely() async {
    final db = await localDatabase.database;
    final apiRows = await db.rawQuery('SELECT COUNT(*) AS c FROM api_cache');
    final mediaRows = await db.rawQuery('SELECT COUNT(*) AS c FROM media_cache');
    final apiCount = (apiRows.first['c'] as num?)?.toInt() ?? 0;
    final mediaCount = (mediaRows.first['c'] as num?)?.toInt() ?? 0;

    await db.transaction((txn) async {
      await txn.delete('api_cache');
      // Preserve summary rows because user ratings, lists, watch states and activity
      // reference media_id. Only invalidate provider detail freshness.
      await txn.update(
        'media_cache',
        {'detail_json': null, 'fetched_at': '1970-01-01T00:00:00.000Z'},
      );
    });

    try { await DefaultCacheManager().emptyCache(); } catch (_) {}
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    return CacheMaintenanceResult(apiEntries: apiCount, mediaEntries: mediaCount);
  }
}
