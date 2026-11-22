import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../modules/registry.dart';
import 'l10n.dart';
import 'module.dart';
import 'widgets.dart';

/// One search result of a module (see [FamilyModule.search]).
class SearchHit {
  const SearchHit({
    required this.title,
    required this.leading,
    required this.open,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget leading;

  /// Goes to the result: switches to its screen and opens it. [context]
  /// belongs to the app shell, so it outlives the search sheet.
  final void Function(BuildContext context, WidgetRef ref) open;
}

/// The search button in the app bar.
class SearchButton extends ConsumerWidget {
  const SearchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
    tooltip: context.l10n.searchTooltip,
    icon: const Icon(Icons.search),
    onPressed: () async {
      final hit = await showSideSheet<SearchHit>(
        context,
        builder: (_) => const _SearchSheet(),
      );
      if (hit != null && context.mounted) hit.open(context, ref);
    },
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _query = TextEditingController();
  Timer? _debounce;

  /// Results per module, in the order of [modules]; null while searching.
  List<(FamilyModule, List<SearchHit>)>? _results = const [];
  bool _failed = false;
  int _generation = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _search);
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    final generation = ++_generation;
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _failed = false;
      });
      return;
    }
    setState(() => _results = null);
    try {
      final hits = await Future.wait([
        for (final m in modules) m.search(context, ref, q),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = false;
        _results = [
          for (var i = 0; i < modules.length; i++)
            if (hits[i].isNotEmpty) (modules[i], hits[i]),
        ];
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = const [];
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final results = _results;
    final muted = TextStyle(color: theme.colorScheme.outline);
    Widget note(String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(text, textAlign: TextAlign.center, style: muted),
    );

    return SideSheetScaffold(
      title: l.searchTooltip,
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onChanged: _changed,
          onSubmitted: (_) {
            _debounce?.cancel();
            _search();
          },
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: l.searchHint,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (results == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_failed)
          note(l.searchFailed)
        else if (results.isEmpty && _query.text.trim().isNotEmpty)
          note(l.searchNothingFound)
        else
          for (final (module, hits) in results) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
              child: Text(
                module.title(l),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            for (final hit in hits)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: hit.leading,
                title: Text(
                  hit.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: hit.subtitle == null
                    ? null
                    : Text(
                        hit.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => Navigator.pop(context, hit),
              ),
          ],
      ],
    );
  }
}
