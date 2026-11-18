import 'dart:async';
import 'dart:convert';

import 'text_store.dart';

/// entity → id → row.
typedef Entities = Map<String, Map<String, Map<String, dynamic>>>;

String viewCacheKey(String view, Map<String, dynamic> params) =>
    '$view ${jsonEncode(params)}';

/// The last known server state of views, kept on the device so the app has
/// something to show before the snapshot arrives (or when it can't).
/// Only the most recently used [maxViews] views are kept.
class ViewCache {
  ViewCache(this.storage, {this.maxViews = 40}) {
    loaded = _load();
  }

  final TextStore storage;
  final int maxViews;
  late final Future<void> loaded;

  // Insertion order = least recently updated first.
  final _views = <String, Entities>{};
  Timer? _flush;
  var _closed = false;

  /// Device storage keys of all view caches start with this (logout clears
  /// them).
  static const keyPrefix = 'oiko.views.';

  Future<void> _load() async {
    try {
      final raw = await storage.load();
      if (raw == null) return;
      final j = (jsonDecode(raw) as Map).cast<String, dynamic>();
      for (final MapEntry(:key, :value) in j.entries) {
        _views.putIfAbsent(key, () => _decode(value));
      }
    } catch (_) {
      // unreadable — start empty
    }
  }

  static Entities _decode(Object? v) => {
    for (final e in (v as Map).entries)
      e.key as String: {
        for (final r in (e.value as Map).entries)
          r.key as String: (r.value as Map).cast<String, dynamic>(),
      },
  };

  /// A copy of the cached state, or null.
  Entities? get(String key) {
    final v = _views[key];
    if (v == null) return null;
    return {for (final e in v.entries) e.key: Map.of(e.value)};
  }

  /// Remembers [state]; it is written out a moment later, so pass the live
  /// map and keep changing it.
  void put(String key, Entities state) {
    if (_closed) return;
    _views.remove(key);
    _views[key] = state;
    while (_views.length > maxViews) {
      _views.remove(_views.keys.first);
    }
    _flush ??= Timer(const Duration(seconds: 2), flush);
  }

  void flush() {
    _flush?.cancel();
    _flush = null;
    if (!_closed) unawaited(storage.save(jsonEncode(_views)));
  }

  /// Stops writing (the last unsaved changes are dropped — on logout the
  /// cache is being deleted anyway).
  void close() {
    _flush?.cancel();
    _closed = true;
  }
}
