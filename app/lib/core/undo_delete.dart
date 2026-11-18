import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n.dart';

/// Keys of things deleted with [deleteWithUndo] whose snackbar is still up.
/// Data providers leave them out, so they disappear at once.
class PendingDeletes extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void add(String key) => state = {...state, key};
  void remove(String key) => state = {...state}..remove(key);
}

final pendingDeletesProvider = NotifierProvider<PendingDeletes, Set<String>>(
  PendingDeletes.new,
);

/// Deletes with an Undo snackbar instead of a confirmation: [key] is hidden
/// right away (see [pendingDeletesProvider]) and [commit] runs only once the
/// snackbar goes away without Undo, so undoing never has to restore anything.
/// Undo calls [onUndo] as well.
void deleteWithUndo(
  BuildContext context, {
  required String key,
  required String message,
  required Future<void> Function() commit,
  VoidCallback? onUndo,
}) {
  // Both outlive the widget that asked (e.g. a sheet that closes now).
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final pending = container.read(pendingDeletesProvider.notifier);
  pending.add(key);
  messenger.hideCurrentSnackBar();
  messenger
      .showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          persist: false, // a snackbar with an action stays put by default
          content: Text(message),
          action: SnackBarAction(
            label: context.l10n.commonUndo,
            onPressed: () {},
          ),
        ),
      )
      .closed
      .then((reason) async {
        if (reason == SnackBarClosedReason.action) {
          pending.remove(key);
          onUndo?.call();
          return;
        }
        try {
          await commit();
        } finally {
          pending.remove(key);
        }
      });
}
