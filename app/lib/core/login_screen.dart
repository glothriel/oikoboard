import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'backend.dart';
import 'family.dart';
import 'l10n.dart';
import 'mock/mock_auth_api.dart';
import 'server_screen.dart';
import 'session.dart';

final _optionsProvider = FutureProvider.autoDispose<AuthOptions>(
  (ref) => ref.watch(authApiProvider).options(),
);

/// The text for a login error shown on the screen.
String _loginErrorText(AppLocalizations l, Object error) => switch (error) {
  LoginError(:final failure) => switch (failure) {
    LoginFailure.staleAttempt => l.loginErrorStale,
    LoginFailure.cancelled => l.loginErrorCancelled,
    LoginFailure.failed => l.loginErrorFailed,
  },
  ApiException(:final message) => message,
  _ => '$error',
};

/// Login screen: Google (+ login by email in dev mode, picking a member in
/// mock mode).
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
      ref.read(loginMessageProvider.notifier).set(e);
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
    final l = context.l10n;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/logo_512.png',
                    width: 96,
                    height: 96,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l.appName,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                invite != null ? l.loginInviteBanner : l.loginTagline,
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
                      _loginErrorText(l, message),
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
                    backend is ApiBackend
                        ? l.loginServerUnreachableAt('${backend.baseUri}')
                        : l.loginServerUnreachable,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: FilledButton.tonal(
                      onPressed: () => ref.invalidate(_optionsProvider),
                      child: Text(l.commonTryAgain),
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
                      label: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(l.loginWithGoogle),
                      ),
                    ),
                  if (!o.google && !o.devLogin && !o.mock)
                    Text(l.loginNoGoogle, textAlign: TextAlign.center),
                  if (o.devLogin) ...[
                    const SizedBox(height: 32),
                    Text(l.loginDevMode, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              labelText: l.loginEmailField,
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            onSubmitted: (_) => _devLogin(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _busy ? null : _devLogin,
                          child: Text(l.loginEnter),
                        ),
                      ],
                    ),
                  ],
                  if (o.mock) ..._mockPicker(theme, l),
                ],
              ),
              if (serverChoice && backend is ApiBackend) ...[
                const SizedBox(height: 24),
                Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: Text(l.loginServerChange(backend.baseUri.host)),
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

  List<Widget> _mockPicker(ThemeData theme, AppLocalizations l) => [
    Text(
      l.loginWhoAreYou,
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
