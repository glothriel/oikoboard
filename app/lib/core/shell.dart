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
import 'l10n.dart';
import 'mock/simulator.dart';
import 'session.dart';
import 'sync/outbox.dart';
import 'unsynced_sheet.dart';

class _Destination {
  const _Destination(this.title, this.icon, this.selectedIcon);
  final String title;
  final IconData icon;
  final IconData selectedIcon;
}

/// Shared frame of the app: the navigation bar (bottom on a phone, side on a
/// wide screen), the app bar and notices about changes by other members.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  StreamSubscription<Exception>? _errors;
  StreamSubscription<FailedMutation>? _failures;

  List<_Destination> _destinations(AppLocalizations l) => [
    _Destination(l.navWall, Icons.dashboard_outlined, Icons.dashboard),
    for (final m in modules) _Destination(m.title(l), m.icon, m.selectedIcon),
  ];

  @override
  void initState() {
    super.initState();
    ref.listenManual(outboxProvider, (_, outbox) {
      _failures?.cancel();
      _failures = outbox?.failures.listen(_onFailure);
    }, fireImmediately: true);
    _errors = ApiClient.errors.stream.listen((error) {
      if (!mounted) return;
      final l = context.l10n;
      final text = switch (error) {
        ApiException(:final message) =>
          message.isEmpty ? l.commonError : message,
        _ => l.commonNoServerConnection,
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );
    });
  }

  void _onFailure(FailedMutation f) {
    if (!mounted) return;
    final l = context.l10n;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(l.syncFailedNotice(describeMutation(l, f.mutation))),
          action: SnackBarAction(
            label: l.syncShow,
            onPressed: () => showUnsyncedSheet(context),
          ),
        ),
      );
  }

  @override
  void dispose() {
    _errors?.cancel();
    _failures?.cancel();
    super.dispose();
  }

  void _onChange(Change change) {
    if (!mounted || change.actorId == ref.read(currentMemberProvider)) return;
    final l = context.l10n;
    final text = modules
        .map((m) => m.describeChange(l, change))
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
              Expanded(
                child: Text(
                  l.shellChangeNotice(member?.name ?? l.commonSomeone, text),
                ),
              ),
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
    final destinations = _destinations(context.l10n);

    final appBar = AppBar(
      title: Text(
        index == 0 ? context.l10n.appName : destinations[index].title,
      ),
      actions: const [
        _UnsyncedButton(),
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
            for (final d in destinations)
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
              for (final d in destinations)
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
      tooltip: on
          ? context.l10n.shellSimulatorStop
          : context.l10n.shellSimulatorStart,
      icon: const Icon(Icons.bolt_outlined),
      selectedIcon: const Icon(Icons.bolt),
      onPressed: () => ref.read(simulatorProvider.notifier).toggle(),
    );
  }
}

/// Avatar in the corner: who is logged in, invitations, switching families
/// (when the account is in several) and logging out. In mock mode — picking a member.
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
        // the shell shows the message (ApiClient.errors)
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
          child: Row(
            children: [
              Icon(Icons.smart_toy_outlined, size: 20),
              SizedBox(width: 12),
              Text(context.l10n.shellAiChat),
            ],
          ),
        ),
        if (!mock)
          PopupMenuItem(
            value: () => showInviteDialog(context),
            child: Row(
              children: [
                Icon(Icons.person_add_alt, size: 20),
                SizedBox(width: 12),
                Text(context.l10n.shellInviteToFamily),
              ],
            ),
          ),
        PopupMenuItem(
          value: () => ref.read(sessionProvider.notifier).logout(),
          child: Row(
            children: [
              Icon(Icons.logout, size: 20),
              SizedBox(width: 12),
              Text(context.l10n.commonLogOut),
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

/// Opens the changes the server rejected; shown only when there are some.
class _UnsyncedButton extends ConsumerWidget {
  const _UnsyncedButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = ref.watch(outboxStateProvider).value?.failed.length ?? 0;
    if (failed == 0) return const SizedBox();
    return IconButton(
      tooltip: context.l10n.syncFailedBadge(failed),
      icon: Badge.count(
        count: failed,
        child: Icon(
          Icons.sync_problem,
          color: Theme.of(context).colorScheme.error,
        ),
      ),
      onPressed: () => showUnsyncedSheet(context),
    );
  }
}

/// Icon shown when there is no connection to the server (data may be stale,
/// changes wait in the outbox).
class _OfflineBadge extends ConsumerWidget {
  const _OfflineBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(onlineProvider).value ?? true;
    if (online) return const SizedBox();
    final pending = ref.watch(outboxStateProvider).value?.pending ?? 0;
    return Tooltip(
      message: pending == 0
          ? context.l10n.shellOffline
          : context.l10n.syncPending(pending),
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
