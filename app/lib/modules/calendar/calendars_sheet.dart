import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';

/// Linked calendars of the family and the user's connected accounts.
Future<void> showCalendarsSheet(BuildContext context, {String? openAccount}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CalendarsSheet(openAccount: openAccount),
    );

class _CalendarsSheet extends ConsumerStatefulWidget {
  const _CalendarsSheet({this.openAccount});
  final String? openAccount;

  @override
  ConsumerState<_CalendarsSheet> createState() => _CalendarsSheetState();
}

class _CalendarsSheetState extends ConsumerState<_CalendarsSheet> {
  late Future<List<CalendarConnection>> _connections = ref
      .read(calendarRepositoryProvider)
      .connections();
  bool _connecting = false;

  void _reload() => setState(() {
    _connections = ref.read(calendarRepositoryProvider).connections();
  });

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      final id = await ref.read(calendarRepositoryProvider).connect();
      if (id != null) _reload();
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(calendarRepositoryProvider);
    final calendars = ref.watch(calendarsProvider).value ?? const [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text('Kalendarze rodziny', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Wydarzenia są zapisywane w podłączonych kalendarzach '
            '(np. Google) — zmiany działają w obie strony. Zadania z terminem '
            'trafiają jako jeden wpis na dzień do kalendarza oznaczonego ✓.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (calendars.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Żaden kalendarz nie jest jeszcze podłączony.'),
            ),
          for (final c in calendars)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ColorDot(c.color, size: 14),
              title: Text(c.name),
              subtitle: Text(
                [
                  if (c.account.isNotEmpty) c.account,
                  if (!c.writable) 'tylko odczyt',
                  if (c.todoTarget) 'zadania z terminem',
                  if (c.syncError.isNotEmpty) '⚠ ${c.syncError}',
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: c.todoTarget
                        ? 'Tu trafiają zadania z terminem'
                        : 'Pokazuj tu zadania z terminem',
                    isSelected: c.todoTarget,
                    icon: const Icon(Icons.checklist),
                    selectedIcon: Icon(
                      Icons.checklist,
                      color: theme.colorScheme.primary,
                    ),
                    onPressed: c.todoTarget || !c.writable
                        ? null
                        : () => repo.setTodoTarget(c.id),
                  ),
                  IconButton(
                    tooltip: 'Synchronizuj teraz',
                    icon: const Icon(Icons.sync),
                    onPressed: () => repo.syncNow(c.id),
                  ),
                  IconButton(
                    tooltip: 'Odłącz od rodziny',
                    icon: const Icon(Icons.link_off),
                    onPressed: () => repo.unlink(c.id),
                  ),
                ],
              ),
            ),
          if (repo.canConnect) ...[
            const Divider(height: 32),
            Text('Twoje konta', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder(
              future: _connections,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return Column(
                  children: [
                    for (final conn in snap.data!)
                      _AccountTile(
                        conn,
                        initiallyExpanded: conn.id == widget.openAccount,
                        onChanged: _reload,
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _connecting ? null : _connect,
              icon: const Icon(Icons.add_link),
              label: const Text('Podłącz konto Google'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A connected account with switches for its calendars.
class _AccountTile extends ConsumerStatefulWidget {
  const _AccountTile(
    this.conn, {
    required this.initiallyExpanded,
    required this.onChanged,
  });
  final CalendarConnection conn;
  final bool initiallyExpanded;
  final VoidCallback onChanged;

  @override
  ConsumerState<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends ConsumerState<_AccountTile> {
  Future<List<RemoteCalendar>>? _remote;

  Future<List<RemoteCalendar>> _fetch() =>
      ref.read(calendarRepositoryProvider).remoteCalendars(widget.conn.id);

  void _load() => setState(() {
    _remote = _fetch();
  });

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) _remote = _fetch();
  }

  Future<void> _toggle(RemoteCalendar rc, bool on) async {
    final repo = ref.read(calendarRepositoryProvider);
    if (on) {
      await repo.link(widget.conn.id, rc.remoteId);
    } else {
      final linked = ref
          .read(calendarsProvider)
          .value
          ?.where(
            (c) =>
                c.connectionId == widget.conn.id && c.remoteId == rc.remoteId,
          )
          .firstOrNull;
      if (linked != null) await repo.unlink(linked.id);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final conn = widget.conn;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ExpansionTile(
        initiallyExpanded: widget.initiallyExpanded,
        onExpansionChanged: (open) {
          if (open && _remote == null) _load();
        },
        leading: Icon(
          conn.revoked ? Icons.error_outline : Icons.account_circle,
        ),
        title: Text(conn.account.isEmpty ? conn.provider : conn.account),
        subtitle: Text(
          conn.revoked
              ? 'Dostęp cofnięty — podłącz konto ponownie'
              : conn.provider == 'mock'
              ? 'konto testowe (mock)'
              : 'Google',
        ),
        children: [
          FutureBuilder(
            future: _remote,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nie udało się pobrać listy kalendarzy.'),
                );
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              return Column(
                children: [
                  for (final rc in snap.data!)
                    SwitchListTile(
                      secondary: ColorDot(rc.color, size: 12),
                      title: Text(rc.name),
                      subtitle: rc.writable ? null : const Text('tylko odczyt'),
                      value: rc.linked,
                      onChanged: (v) => _toggle(rc, v),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      await ref
                          .read(calendarRepositoryProvider)
                          .disconnect(conn.id);
                      widget.onChanged();
                    },
                    icon: const Icon(Icons.logout),
                    label: const Text('Odłącz konto (usuwa jego kalendarze)'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
