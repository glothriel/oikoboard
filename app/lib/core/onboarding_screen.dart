import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'session.dart';

/// Po zalogowaniu, gdy konto nie ma jeszcze rodziny (albo przyszło
/// z linkiem zaproszenia): dołącz do rodziny albo załóż nową.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _family = TextEditingController();
  final _me = TextEditingController();
  final _link = TextEditingController();
  bool _busy = false;
  String? _linkError;

  @override
  void dispose() {
    _family.dispose();
    _me.dispose();
    _link.dispose();
    super.dispose();
  }

  Session get _session => ref.read(sessionProvider)!;

  Future<void> _run(Future<Session> Function(AuthApi api) action) async {
    setState(() => _busy = true);
    try {
      final s = await action(ref.read(authApiProvider));
      ref.read(sessionProvider.notifier).set(s);
    } on ApiException catch (e) {
      if (e.status == 401) {
        ref.read(sessionProvider.notifier).logout();
      } else {
        _snack(e.message);
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _create() {
    final name = _family.text.trim();
    if (name.isEmpty) return;
    _run((api) => api.createHousehold(_session, name, _me.text.trim()));
  }

  void _useLink() {
    final token = parseInvite(_link.text);
    setState(
      () => _linkError = token == null
          ? 'To nie wygląda na link z zaproszeniem'
          : null,
    );
    if (token != null) ref.read(pendingInviteProvider.notifier).set(token);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider)!;
    final invite = ref.watch(pendingInviteProvider);
    final firstName = session.user.name.split(' ').first;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                firstName.isEmpty ? 'Cześć!' : 'Cześć, $firstName!',
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      session.user.email,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).logout(),
                    child: const Text('Wyloguj'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (invite != null)
                _InviteCard(
                  key: ValueKey(invite),
                  token: invite,
                  busy: _busy,
                  onAccept: () async {
                    await _run((api) => api.acceptInvite(_session, invite));
                    if (ref.read(sessionProvider)?.householdId != null) {
                      ref.read(pendingInviteProvider.notifier).set(null);
                    }
                  },
                  onDismiss: () =>
                      ref.read(pendingInviteProvider.notifier).set(null),
                )
              else if (!session.hasHousehold) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Załóż rodzinę',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Potem zaprosisz resztę domowników linkiem.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _family,
                          decoration: const InputDecoration(
                            labelText: 'Nazwa rodziny',
                            hintText: 'np. Kowalscy',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _me,
                          decoration: InputDecoration(
                            labelText: 'Jak cię nazywać w rodzinie?',
                            hintText: firstName.isEmpty
                                ? 'np. Tata'
                                : 'np. Tata (domyślnie: $firstName)',
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _create(),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            onPressed: _busy ? null : _create,
                            child: const Text('Załóż'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Masz zaproszenie?',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Otwórz link od domownika albo wklej go tutaj.',
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _link,
                          decoration: InputDecoration(
                            labelText: 'Link z zaproszeniem',
                            border: const OutlineInputBorder(),
                            errorText: _linkError,
                          ),
                          onSubmitted: (_) => _useLink(),
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: _busy ? null : _useLink,
                            child: const Text('Dalej'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

final _invitePreviewProvider = FutureProvider.autoDispose
    .family<InvitePreview, String>((ref, token) {
      final session = ref.watch(sessionProvider)!;
      return ref.watch(authApiProvider).previewInvite(session, token);
    });

class _InviteCard extends ConsumerWidget {
  const _InviteCard({
    super.key,
    required this.token,
    required this.busy,
    required this.onAccept,
    required this.onDismiss,
  });

  final String token;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preview = ref.watch(_invitePreviewProvider(token));
    final session = ref.watch(sessionProvider)!;
    final dismissLabel = session.hasHousehold
        ? 'Wróć do: ${session.householdName}'
        : 'Odrzuć';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: preview.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Zaproszenie', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                e is ApiException
                    ? e.message
                    : 'Nie udało się sprawdzić zaproszenia.',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onDismiss,
                  child: Text(dismissLabel),
                ),
              ),
            ],
          ),
          data: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Zaproszenie do rodziny', style: theme.textTheme.labelLarge),
              Text(p.householdName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              if (p.invitedBy != null) Text('Zaprasza: ${p.invitedBy}'),
              if (p.memberName != null) Text('Dołączysz jako: ${p.memberName}'),
              if (p.alreadyMember) const Text('Już należysz do tej rodziny.'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onDismiss, child: Text(dismissLabel)),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: busy ? null : onAccept,
                    child: Text(p.alreadyMember ? 'Przejdź' : 'Dołącz'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
