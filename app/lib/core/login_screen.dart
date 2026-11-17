import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'backend.dart';
import 'family.dart';
import 'mock/mock_auth_api.dart';
import 'server_screen.dart';
import 'session.dart';

final _optionsProvider = FutureProvider.autoDispose<AuthOptions>(
  (ref) => ref.watch(authApiProvider).options(),
);

/// Ekran logowania: Google (+ logowanie e-mailem w trybie dev, wybór
/// osoby w trybie mock).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Session?> Function(AuthApi api) login) async {
    setState(() => _busy = true);
    ref.read(loginMessageProvider.notifier).set(null);
    try {
      final s = await login(ref.read(authApiProvider));
      if (s != null) ref.read(sessionProvider.notifier).set(s);
    } catch (e) {
      ref.read(loginMessageProvider.notifier).set('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = ref.watch(_optionsProvider);
    final backend = ref.watch(backendProvider);
    final message = ref.watch(loginMessageProvider);
    final invite = ref.watch(pendingInviteProvider);
    final serverChoice = ref.watch(serverChoiceProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Icon(
                Icons.home_work_outlined,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 12),
              Text(
                'Oikoboard',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                invite != null
                    ? 'Masz zaproszenie do rodziny — zaloguj się, żeby dołączyć.'
                    : 'Wspólna tablica rodziny.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              if (message != null) ...[
                Card(
                  color: theme.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              ...options.when(
                loading: () => [
                  const Center(child: CircularProgressIndicator()),
                ],
                error: (e, _) => [
                  Text(
                    'Nie mogę połączyć się z serwerem'
                    '${backend is ApiBackend ? ' (${backend.baseUri})' : ''}.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.tonal(
                      onPressed: () => ref.invalidate(_optionsProvider),
                      child: const Text('Spróbuj ponownie'),
                    ),
                  ),
                ],
                data: (o) => [
                  if (o.google)
                    FilledButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run((api) => api.loginWithGoogle()),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Zaloguj się przez Google'),
                      ),
                    ),
                  if (!o.google && !o.devLogin && !o.mock)
                    const Text(
                      'Serwer nie ma skonfigurowanego logowania '
                      '(OIKO_GOOGLE_CLIENT_ID).',
                      textAlign: TextAlign.center,
                    ),
                  if (o.devLogin) ...[
                    const SizedBox(height: 32),
                    Text(
                      'Tryb deweloperski',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-mail (bez weryfikacji)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _devLogin(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy ? null : _devLogin,
                          child: const Text('Wejdź'),
                        ),
                      ],
                    ),
                  ],
                  if (o.mock) ..._mockPicker(theme),
                ],
              ),
              if (serverChoice && backend is ApiBackend) ...[
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: Text('Serwer: ${backend.baseUri.host} — zmień'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ServerScreen()),
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

  void _devLogin() {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    _run((api) => api.devLogin(email));
  }

  List<Widget> _mockPicker(ThemeData theme) => [
    Text(
      'Kim jesteś? (tryb mock)',
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium,
    ),
    const SizedBox(height: 16),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final m in mockFamily)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _busy ? null : () => _run((api) => api.mockLogin(m.id)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  MemberAvatar(m, radius: 24),
                  const SizedBox(height: 6),
                  Text(m.name),
                ],
              ),
            ),
          ),
      ],
    ),
  ];
}
