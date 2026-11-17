import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../modules/registry.dart';
import 'api/api_client.dart';
import 'ai/ai_screen.dart';
import 'backend.dart';
import 'change.dart';
import 'data.dart';
import 'family.dart';
import 'invite_dialog.dart';
import 'mock/simulator.dart';
import 'session.dart';

class _Destination {
  const _Destination(this.title, this.icon, this.selectedIcon);
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

/// Wspólna rama aplikacji: pasek nawigacji (dół na telefonie, bok na
/// szerokim ekranie), app bar i powiadomienia o zmianach od innych osób.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<String>? _errors;

  final _destinations = [
    const _Destination('Ściana', Icons.dashboard_outlined, Icons.dashboard),
    for (final m in modules) _Destination(m.title, m.icon, m.selectedIcon),
  ];

  @override
  void initState() {
    super.initState();
    _errors = ApiClient.errors.stream.listen((msg) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(msg)),
      );
    });
  }

  @override
  void dispose() {
    _errors?.cancel();
    super.dispose();
  }

  void _onChange(Change change) {
    if (!mounted || change.actorId == ref.read(currentMemberProvider)) return;
    final text = modules
        .map((m) => m.describeChange(change))
        .nonNulls
        .firstOrNull;
    if (text == null) return;
    final member = ref.read(familyProvider).byId(change.actorId);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              if (member != null) MemberAvatar(member, radius: 12),
              const SizedBox(width: 12),
              // not a current member (e.g. removed since)
              Expanded(child: Text('${member?.name ?? 'Ktoś'}: $text')),
            ],
          ),
        ),
      );
  }

  void _go(int index) => widget.navigationShell.goBranch(
    index,
    initialLocation: index == widget.navigationShell.currentIndex,
  );

  @override
  Widget build(BuildContext context) {
    ref.listen(changeEventsProvider, (_, next) {
      if (next.value case final change?) _onChange(change);
    });
    final index = widget.navigationShell.currentIndex;
    final width = MediaQuery.sizeOf(context).width;

    final appBar = AppBar(
      title: Text(index == 0 ? 'Oikoboard' : _destinations[index].title),
      actions: const [
        _OfflineBadge(),
        _SimulatorButton(),
        _AccountMenu(),
        SizedBox(width: 8),
      ],
    );

    if (width < 720) {
      return Scaffold(
        appBar: appBar,
        body: widget.navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selectedIcon),
                label: d.title,
              ),
          ],
        ),
      );
    }

    final extended = width >= 1100;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: _go,
            extended: extended,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Icon(
                Icons.home_work_outlined,
                size: 32,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            destinations: [
              for (final d in _destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: Text(d.title),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Scaffold(appBar: appBar, body: widget.navigationShell),
          ),
        ],
      ),
    );
  }
}

class _SimulatorButton extends ConsumerWidget {
  const _SimulatorButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(backendProvider) is! MockBackend) return const SizedBox();
    final on = ref.watch(simulatorProvider);
    return IconButton(
      isSelected: on,
      tooltip: on ? 'Zatrzymaj symulację rodziny' : 'Symuluj zmiany od rodziny',
      icon: const Icon(Icons.bolt_outlined),
      selectedIcon: const Icon(Icons.bolt),
      onPressed: () => ref.read(simulatorProvider.notifier).toggle(),
    );
  }
}

/// Avatar w rogu: kto jest zalogowany, zaproszenia, przełączanie rodzin
/// (gdy konto jest w kilku) i wylogowanie. W trybie mock — wybór osoby.
class _AccountMenu extends ConsumerWidget {
  const _AccountMenu();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider)!;
    final me = session.me;
    final mock = ref.watch(backendProvider) is MockBackend;

    Future<void> switchTo(String memberId) async {
      try {
        final s = await ref
            .read(authApiProvider)
            .switchMember(session, memberId);
        ref.read(sessionProvider.notifier).set(s);
      } catch (_) {
        // komunikat pokazuje shell (ApiClient.errors)
      }
    }

    return PopupMenuButton<VoidCallback>(
      tooltip: session.user.email,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: MemberAvatar(me, radius: 16),
            title: Text('${me.name} · ${session.householdName}'),
            subtitle: mock ? null : Text(session.user.email),
          ),
        ),
        if (mock) ...[
          const PopupMenuDivider(),
          for (final m in session.members)
            PopupMenuItem(
              value: () => switchTo(m.id),
              child: Row(
                children: [
                  MemberAvatar(m, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m.name)),
                  if (m.id == me.id) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
        if (session.memberships.length > 1) ...[
          const PopupMenuDivider(),
          for (final ms in session.memberships)
            PopupMenuItem(
              value: () => switchTo(ms.memberId),
              child: Row(
                children: [
                  const Icon(Icons.home_outlined, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(ms.householdName)),
                  if (ms.memberId == me.id) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => openAiScreen(context),
          child: const Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 20),
              SizedBox(width: 12),
              Text('Czat AI (MCP)'),
            ],
          ),
        ),
        if (!mock)
          PopupMenuItem(
            value: () => showInviteDialog(context),
            child: const Row(
              children: [
                Icon(Icons.person_add_alt, size: 20),
                SizedBox(width: 12),
                Text('Zaproś do rodziny'),
              ],
            ),
          ),
        PopupMenuItem(
          value: () => ref.read(sessionProvider.notifier).logout(),
          child: const Row(
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 12),
              Text('Wyloguj'),
            ],
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: MemberAvatar(me, radius: 16),
      ),
    );
  }
}

/// Ikonka, gdy nie ma połączenia z serwerem (dane mogą być nieaktualne).
class _OfflineBadge extends ConsumerWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? true;
    if (online) return const SizedBox();
    return Tooltip(
      message: 'Brak połączenia — łączę ponownie…',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          Icons.cloud_off,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
    );
  }
}
