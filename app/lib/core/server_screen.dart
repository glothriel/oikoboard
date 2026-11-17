import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'backend.dart';
import 'l10n.dart';
import 'session.dart';

/// First start on Android/desktop: which server (the family's own instance).
/// Also reachable from the login screen (“change server”).
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  late final _url = TextEditingController(
    text:
        ref.read(serverUrlProvider)?.toString() ??
        (kDebugMode ? 'http://localhost:8090' : ''),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final url = parseServerUrl(_url.text);
    if (url == null) {
      setState(() => _error = context.l10n.serverNotAnAddress);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await http
          .get(url.resolve('/api/v1/health'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200 || !res.body.contains('"ok"')) {
        throw Exception('HTTP ${res.statusCode}');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.l10n.serverNotOikoboard('$url');
        });
      }
      return;
    }
    // A session belongs to one server.
    await ref.read(sessionProvider.notifier).logout();
    await ref.read(serverUrlProvider.notifier).set(url);
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: Navigator.of(context).canPop() ? AppBar() : null,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.dns_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                context.l10n.serverTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.serverIntro,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _url,
                autofocus: true,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: context.l10n.serverAddressLabel,
                  errorText: _error,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => _busy ? null : _connect(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _connect,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.l10n.commonConnect),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
