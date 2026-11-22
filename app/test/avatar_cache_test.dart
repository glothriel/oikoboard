import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:oikoboard/core/avatar_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const url = 'https://example.com/a.png';
  final png = [0x89, 0x50, 0x4e, 0x47];

  setUp(AvatarCache.reset);

  test('fetches once, stores, and loads after a restart', () async {
    SharedPreferences.setMockInitialValues({});
    var fetches = 0;
    await http.runWithClient(
      () async {
        expect(AvatarCache.image(url), isA<NetworkImage>());
        AvatarCache.image(url); // not fetched twice
        await pumpEventQueue();
      },
      () => MockClient((_) async {
        fetches++;
        return http.Response.bytes(
          png,
          200,
          headers: {'content-type': 'image/png'},
        );
      }),
    );
    expect(fetches, 1);
    expect(AvatarCache.image(url), isA<MemoryImage>());

    // Next start: from the device, without the network.
    AvatarCache.reset();
    await AvatarCache.load();
    final stored = AvatarCache.cached(url);
    expect(stored, isA<MemoryImage>());
    expect((stored! as MemoryImage).bytes, png);
  });

  test('keeps nothing that is not an image', () async {
    SharedPreferences.setMockInitialValues({});
    await http.runWithClient(
      () async {
        AvatarCache.image(url);
        await pumpEventQueue();
      },
      () => MockClient(
        (_) async => http.Response(
          jsonEncode({'error': 'x'}),
          404,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    expect(AvatarCache.cached(url), isNull);
  });
}
