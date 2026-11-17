import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'api/api_client.dart';
import 'family.dart';
import 'l10n.dart';
import 'session.dart';

/// “Invite to family”: a link for a new person, or for a member without an account.
Future<void> showInviteDialog(BuildContext context) =>
    showDialog(context: context, builder: (_) => const _InviteDialog());

class _InviteDialog extends ConsumerStatefulWidget {
  const _InviteDialog();

  @override
  ConsumerState<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends ConsumerState<_InviteDialog> {
  String? _memberId; // null = a new person
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
      // the shell shows the message (ApiClient.errors)
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider)!;
    final withoutAccount = session.members.where((m) => !m.hasAccount).toList();
    final invite = _invite;
    final l = context.l10n;

    return AlertDialog(
      title: Text(l.inviteTitle(session.householdName ?? '')),
      content: SizedBox(
        width: 420,
        child: invite == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.inviteWhom),
                  const SizedBox(height: 8),
                  RadioGroup<String?>(
                    groupValue: _memberId,
                    onChanged: (v) => setState(() => _memberId = v),
                    child: Column(
                      children: [
                        RadioListTile<String?>(
                          value: null,
                          title: Text(l.inviteNewPerson),
                          subtitle: Text(l.inviteNewPersonHint),
                        ),
                        for (final Member m in withoutAccount)
                          RadioListTile<String?>(
                            value: m.id,
                            secondary: MemberAvatar(m, radius: 14),
                            title: Text(m.name),
                            subtitle: Text(l.inviteMemberNoAccount),
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
                  Text(l.inviteSendLink),
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
                child: Text(l.commonCancel),
              ),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: Text(l.inviteCreateLink),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.commonClose),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.copy, size: 18),
                label: Text(l.commonCopy),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: invite.link));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(l.inviteLinkCopied)));
                },
              ),
            ],
    );
  }
}
