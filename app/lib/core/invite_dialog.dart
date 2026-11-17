import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'family.dart';
import 'session.dart';

/// „Zaproś do rodziny”: link dla nowej osoby albo dla członka bez konta.
Future<void> showInviteDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _InviteDialog());

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog();

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  String? _memberId; // null = nowa osoba
  bool _busy = false;
  CreatedInvite? _invite;

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final inv = await ref
          .read(authApiProvider)
          .createInvite(ref.read(sessionProvider)!, memberId: _memberId);
      setState(() => _invite = inv);
    } on ApiException {
      // komunikat pokazuje shell (ApiClient.errors)
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final withoutAccount = session.members.where((m) => !m.hasAccount).toList();
    final invite = _invite;

    return AlertDialog(
      title: Text('Zaproś do: ${session.householdName}'),
      content: SizedBox(
        width: 420,
        child: invite == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Kogo zapraszasz?'),
                  const SizedBox(height: 8),
                  RadioGroup<String?>(
                    groupValue: _memberId,
                    onChanged: (v) => setState(() => _memberId = v),
                    child: Column(
                      children: [
                        const RadioListTile<String?>(
                          value: null,
                          title: Text('Nową osobę'),
                          subtitle: Text('Sama wybierze, jak ją nazywać'),
                        ),
                        for (final Member m in withoutAccount)
                          RadioListTile<String?>(
                            value: m.id,
                            secondary: MemberAvatar(m, radius: 14),
                            title: Text(m.name),
                            subtitle: const Text(
                              'Jest w rodzinie, nie ma konta',
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Wyślij ten link domownikowi. Działa raz, przez 7 dni.',
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    invite.link,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ],
              ),
      ),
      actions: invite == null
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Anuluj'),
              ),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: const Text('Utwórz link'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Zamknij'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Kopiuj'),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.link));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Skopiowano link')),
                  );
                },
              ),
            ],
    );
  }
}
