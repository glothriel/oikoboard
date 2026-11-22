import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Profile pictures kept on the device, so avatars show offline and without
/// the initial flashing while a picture loads. Pictures are small (Google's
/// default ~100 px), so they live in the device preferences, keyed by URL
/// (a changed picture has a new URL); the most recently stored [_max] stay.
abstract final class AvatarCache {
  static const _prefix = 'oiko.avatar.';
  static const _indexKey = 'oiko.avatar_index';
  static const _max = 64;
  static const _maxBytes = 256 * 1024;

  static final _images = <String, MemoryImage>{};

  /// Tried this run (fetched or failed): not retried until the next start.
  static final _tried = <String>{};

  /// Loads the stored pictures; call before the first frame.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final url in prefs.getStringList(_indexKey) ?? const <String>[]) {
        final data = prefs.getString('$_prefix$url');
        if (data != null) _images[url] = MemoryImage(base64Decode(data));
      }
    } catch (_) {}
  }

  /// The stored picture, if there is one.
  static ImageProvider? cached(String url) => _images[url];

  /// The picture at [url]: the stored copy, else from the network — and
  /// stored in the background for next time.
  static ImageProvider image(String url) {
    final cached = _images[url];
    if (cached != null) return cached;
    if (_tried.add(url)) _fetch(url);
    return NetworkImage(url);
  }

  static Future<void> _fetch(String url) async {
    try {
      final res = await http.get(Uri.parse(url));
      final type = res.headers['content-type'] ?? '';
      final bytes = res.bodyBytes;
      if (res.statusCode != 200 ||
          !type.startsWith('image/') ||
          bytes.isEmpty ||
          bytes.length > _maxBytes) {
        return;
      }
      _images[url] = MemoryImage(bytes);
      final prefs = await SharedPreferences.getInstance();
      final index = [
        ...?prefs.getStringList(_indexKey)?.where((u) => u != url),
        url,
      ];
      while (index.length > _max) {
        await prefs.remove('$_prefix${index.removeAt(0)}');
      }
      await prefs.setString('$_prefix$url', base64Encode(bytes));
      await prefs.setStringList(_indexKey, index);
    } catch (_) {
      // Offline, or (web) the host doesn't allow reading it: the network
      // image still shows when it can.
    }
  }

  @visibleForTesting
  static void reset() {
    _images.clear();
    _tried.clear();
  }
}
