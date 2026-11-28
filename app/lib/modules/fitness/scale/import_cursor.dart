import '../../../core/device_prefs.dart';

DateTime _minute(DateTime t) =>
    DateTime(t.year, t.month, t.day, t.hour, t.minute);

/// The last imported reading time of one scale (by its device id), at minute
/// resolution, kept on this device. Readings at or before it are duplicates.
class ImportCursor {
  ImportCursor._(this.scaleId, this._last);

  final String scaleId;
  DateTime? _last;

  static String _key(String id) => 'fitness.scale.lastImported.$id';

  static Future<ImportCursor> load(String scaleId) async {
    final v = await DevicePrefs.get(_key(scaleId));
    final ms = v == null ? null : int.tryParse(v);
    return ImportCursor._(
      scaleId,
      ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms),
    );
  }

  DateTime? get last => _last;

  /// False for a scale this device has never imported from.
  bool get isKnown => _last != null;

  bool isNew(DateTime t) => _last == null || _minute(t).isAfter(_last!);

  /// Moves the cursor forward (never back) to [t].
  Future<void> advance(DateTime t) async {
    final m = _minute(t);
    if (_last != null && !m.isAfter(_last!)) return;
    _last = m;
    await DevicePrefs.set(_key(scaleId), m.millisecondsSinceEpoch.toString());
  }
}
