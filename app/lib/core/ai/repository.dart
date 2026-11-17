import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../backend.dart';
import '../data.dart';

/// An app (e.g. ChatGPT) the signed-in member connected over OAuth.
class ConnectedApp {
  const ConnectedApp(this.id, this.client, this.createdAt, this.lastUsedAt);
  final String id;
  final String client;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  factory ConnectedApp.fromJson(Map<String, dynamic> j) => ConnectedApp(
    j['id'] as String,
    j['client'] as String,
    fromApiTime(j['created_at'])!,
    fromApiTime(j['last_used_at']),
  );
}

abstract interface class AiRepository {
  /// The MCP endpoint for apps like ChatGPT or Claude (null in mock mode).
  String? get mcpUrl;

  /// The signed-in member's connected apps.
  Future<List<ConnectedApp>> connectedApps();
  Future<void> disconnectApp(String id);
}

class ApiAiRepository implements AiRepository {
  ApiAiRepository(this.api);
  final ApiClient api;

  @override
  String get mcpUrl => api.baseUri.resolve('/mcp').toString();

  @override
  Future<List<ConnectedApp>> connectedApps() async => [
    for (final j in (await api.get('/oauth/grants') as List).cast<Map>())
      ConnectedApp.fromJson(j.cast()),
  ];

  @override
  Future<void> disconnectApp(String id) => api.delete('/oauth/grants/$id');
}

/// No server: one sample connected app, kept in memory.
class MockAiRepository implements AiRepository {
  static final _apps = [
    ConnectedApp('mock-chatgpt', 'ChatGPT', DateTime(2026, 1, 1), null),
  ];

  @override
  String? get mcpUrl => null;

  @override
  Future<List<ConnectedApp>> connectedApps() async => List.of(_apps);

  @override
  Future<void> disconnectApp(String id) async =>
      _apps.removeWhere((a) => a.id == id);
}

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => switch (ref.watch(backendProvider)) {
    MockBackend() => MockAiRepository(),
    ApiBackend() => ApiAiRepository(ref.watch(apiClientProvider)),
  },
);
