import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'l10n.dart';

/// A module's card on the home screen.
class WallCard extends StatelessWidget {
  const WallCard({
    super.key,
    required this.title,
    required this.icon,
    required this.path,
    required this.child,
  });

  final String title;
  final IconData icon;
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.go(path),
                  child: Text(context.l10n.commonOpen),
                ),
              ],
            ),
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
          ],
        ),
      ),
    );
  }
}

class ColorDot extends StatelessWidget {
  const ColorDot(this.color, {super.key, this.size = 10});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// A Material 3 modal side sheet for a separate view (e.g. a task's comments):
/// slides in from the right, 480 px wide on wide screens and full-screen on
/// phones. [builder] usually returns a [SideSheetScaffold].
Future<T?> showSideSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showGeneralDialog<T>(
  context: context,
  barrierDismissible: true,
  barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
  barrierColor: Colors.black38,
  transitionDuration: const Duration(milliseconds: 250),
  pageBuilder: (context, _, _) => LayoutBuilder(
    builder: (context, constraints) {
      final full = constraints.maxWidth < 600;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: full ? constraints.maxWidth : 480,
          height: constraints.maxHeight,
          child: Material(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            borderRadius: full
                ? BorderRadius.zero
                : const BorderRadius.horizontal(left: Radius.circular(16)),
            child: builder(context),
          ),
        ),
      );
    },
  ),
  transitionBuilder: (context, animation, _, child) => SlideTransition(
    position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    child: child,
  ),
);

/// The layout of a side sheet: a header with close, title and [actions],
/// a scrolling [children] body and an optional [bottom] pinned under it.
class SideSheetScaffold extends StatelessWidget {
  const SideSheetScaffold({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: context.l10n.commonClose,
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(title),
      actions: [...actions, const SizedBox(width: 8)],
    ),
    body: Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: children,
          ),
        ),
        ?bottom,
      ],
    ),
  );
}

/// An editor in a modal bottom sheet (thumb-friendly on phones); [builder]
/// usually returns an [EditorSheet].
Future<T?> showEditorSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  useSafeArea: true,
  builder: builder,
);

/// The layout of an editor sheet: a title, the scrolling [children] and a
/// bar at the bottom with [actions] on the left and [primary] on the right.
class EditorSheet extends StatelessWidget {
  const EditorSheet({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.primary,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final Widget? primary;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
            child: Row(children: [...actions, const Spacer(), ?primary]),
          ),
        ),
      ],
    ),
  );
}

/// Asks before deleting (or otherwise removing) something; true when confirmed.
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  String? message,
  String? action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) {
        final colors = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(title),
          content: message == null ? null : Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action ?? context.l10n.commonDelete),
            ),
          ],
        );
      },
    ) ??
    false;
