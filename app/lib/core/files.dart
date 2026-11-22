import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'api/api_client.dart';
import 'backend.dart';
import 'session.dart';

/// An uploaded file (the server's `files`, without the data).
class StoredFile {
  const StoredFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
  });

  final String id;
  final String name;
  final String mime;
  final int size;

  /// A picture the app can show.
  bool get isImage => const {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  }.contains(mime);

  factory StoredFile.fromJson(Map<String, dynamic> j) => StoredFile(
    id: j['id'] as String,
    name: j['name'] as String,
    mime: j['mime'] as String,
    size: (j['size'] as num).toInt(),
  );
}

/// How much of the family's storage is used, in bytes.
typedef StorageUsage = ({int used, int quota});

/// The upload is larger than [maxFileSize].
class FileTooLargeException implements Exception {
  const FileTooLargeException();
}

/// The family's storage quota is used up.
class StorageFullException implements Exception {
  const StorageFullException();
}

/// The largest single upload (as on the server).
const maxFileSize = 25 << 20;

/// Uploaded files of the family (`/files` on the server).
abstract interface class FileStore {
  /// Throws [FileTooLargeException], [StorageFullException] or a network error.
  Future<StoredFile> upload(Uint8List bytes, String name);

  /// The file's content (cached for a while).
  Future<Uint8List> bytes(String id);

  /// A short-lived URL that opens or downloads the file in a browser; null
  /// when there is none (mock).
  Future<Uri?> link(String id);

  Future<StorageUsage> usage();
}

/// The most recently used file contents, so thumbnails don't load again
/// every time they show.
class _BytesCache {
  final _map = <String, Future<Uint8List>>{}; // insertion-ordered
  static const _max = 60;

  Future<Uint8List> get(String id, Future<Uint8List> Function() load) {
    final hit = _map.remove(id);
    final f = hit ?? load();
    _map[id] = f;
    // A failed load isn't kept: the next look tries again.
    f.catchError((Object _) {
      if (identical(_map[id], f)) _map.remove(id);
      return Uint8List(0);
    });
    while (_map.length > _max) {
      _map.remove(_map.keys.first);
    }
    return f;
  }
}

class ApiFileStore implements FileStore {
  ApiFileStore(this.baseUri, this.token);
  final Uri baseUri;
  final String token;
  final _http = http.Client();
  final _cache = _BytesCache();

  Uri _uri(String path) => baseUri.resolve('/api/v1$path');
  Map<String, String> get _auth => {'Authorization': 'Bearer $token'};

  Never _fail(http.BaseResponse res, List<int> body) {
    var code = '', msg = res.reasonPhrase ?? '';
    try {
      final j = jsonDecode(utf8.decode(body)) as Map;
      code = j['error'] as String? ?? '';
      msg = j['message'] as String? ?? msg;
    } catch (_) {}
    if (code == 'quota_exceeded') throw const StorageFullException();
    if (code == 'too_large' || res.statusCode == 413) {
      throw const FileTooLargeException();
    }
    throw ApiException(res.statusCode, msg);
  }

  @override
  Future<StoredFile> upload(Uint8List bytes, String name) async {
    if (bytes.length > maxFileSize) throw const FileTooLargeException();
    final req = http.MultipartRequest('POST', _uri('/files'))
      ..headers.addAll(_auth)
      ..fields['id'] = uuid.v4()
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: name));
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode >= 400) _fail(res, res.bodyBytes);
    final file = StoredFile.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>,
    );
    _cache.get(file.id, () async => bytes); // just uploaded: no need to fetch
    return file;
  }

  @override
  Future<Uint8List> bytes(String id) => _cache.get(id, () async {
    final res = await _http.get(_uri('/files/$id'), headers: _auth);
    if (res.statusCode >= 400) _fail(res, res.bodyBytes);
    return res.bodyBytes;
  });

  @override
  Future<Uri?> link(String id) async {
    final res = await _http.post(_uri('/files/$id/link'), headers: _auth);
    if (res.statusCode >= 400) _fail(res, res.bodyBytes);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return baseUri.resolve(j['url'] as String);
  }

  @override
  Future<StorageUsage> usage() async {
    final res = await _http.get(_uri('/files/usage'), headers: _auth);
    if (res.statusCode >= 400) _fail(res, res.bodyBytes);
    final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (
      used: (j['used'] as num).toInt(),
      quota: (j['quota'] as num).toInt(),
    );
  }

  void close() => _http.close();
}

/// Files in memory (the mock backend): nothing leaves the device.
class MockFileStore implements FileStore {
  MockFileStore({this.quota = 1 << 30});
  final int quota;
  final _files = <String, (StoredFile, Uint8List)>{};

  @override
  Future<StoredFile> upload(Uint8List bytes, String name) async {
    if (bytes.length > maxFileSize) throw const FileTooLargeException();
    if ((await usage()).used + bytes.length > quota) {
      throw const StorageFullException();
    }
    final file = StoredFile(
      id: uuid.v4(),
      name: name,
      mime: mimeFromName(name),
      size: bytes.length,
    );
    _files[file.id] = (file, bytes);
    return file;
  }

  @override
  Future<Uint8List> bytes(String id) async =>
      _files[id]?.$2 ?? (throw ApiException(404, 'not found'));

  @override
  Future<Uri?> link(String id) async => null;

  @override
  Future<StorageUsage> usage() async =>
      (used: _files.values.fold(0, (sum, f) => sum + f.$1.size), quota: quota);
}

/// The type of a file by its extension (the mock; the server decides itself).
String mimeFromName(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };
}

final _mockFiles = MockFileStore();

final fileStoreProvider = Provider<FileStore>((ref) {
  switch (ref.watch(backendProvider)) {
    case MockBackend():
      return _mockFiles;
    case ApiBackend(:final baseUri):
      final store = ApiFileStore(baseUri, ref.watch(sessionProvider)!.token);
      ref.onDispose(store.close);
      return store;
  }
});
