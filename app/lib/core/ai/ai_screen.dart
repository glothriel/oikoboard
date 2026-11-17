import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../api/api_client.dart';
import 'repository.dart';

/// "AI": connect your own AI chat (ChatGPT, Claude…) over MCP + OAuth, and
/// see or disconnect the apps you connected.
Future<void> openAiScreen(BuildContext context) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const AiScreen()));

class AiScreen extends StatelessWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ChatGPT, Claude i inne')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: const [_ConnectedApps()],
        ),
      ),
    ),
  );
}

class _ConnectedApps extends ConsumerStatefulWidget {
  const _ConnectedApps();

  @override
  ConsumerState<_ConnectedApps> createState() => _ConnectedAppsState();
}

class _ConnectedAppsState extends ConsumerState<_ConnectedApps> {
  late Future<List<ConnectedApp>> _apps = ref
      .read(aiRepositoryProvider)
      .connectedApps();

  Future<void> _disconnect(ConnectedApp app) async {
    try {
      await ref.read(aiRepositoryProvider).disconnectApp(app.id);
    } on ApiException {
      return; // the shell shows the message
    }
    setState(() {
      _apps = ref.read(aiRepositoryProvider).connectedApps();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = ref.watch(aiRepositoryProvider).mcpUrl;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Twoje zadania i kalendarz rodziny możesz podłączyć też do '
              'własnego czatu AI. Dodaj w nim konektor (MCP) z tym adresem — '
              'zalogujesz się kontem Oikoboard, a zmiany będą zapisywane '
              'jako Twoje.',
              style: theme.textTheme.bodySmall,
            ),
            if (url != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      url,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kopiuj adres',
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: url));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Skopiowano adres')),
                      );
                    },
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            FutureBuilder(
              future: _apps,
              builder: (context, snap) {
                final apps = snap.data ?? const <ConnectedApp>[];
                if (apps.isEmpty) {
                  return Text(
                    snap.connectionState == ConnectionState.done
                        ? 'Nic nie jest podłączone.'
                        : '…',
                    style: theme.textTheme.bodySmall,
                  );
                }
                return Column(
                  children: [
                    for (final a in apps)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link),
                        title: Text(a.client),
                        subtitle: Text(
                          a.lastUsedAt == null
                              ? 'Jeszcze nieużywane'
                              : 'Ostatnio: ${_when(a.lastUsedAt!)}',
                        ),
                        trailing: TextButton(
                          onPressed: () => _disconnect(a),
                          child: const Text('Odłącz'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  static String _when(DateTime d) =>
      '${d.day}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
}
