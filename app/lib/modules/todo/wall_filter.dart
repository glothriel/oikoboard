import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/device_prefs.dart';
import '../../core/family.dart';
import '../../core/l10n.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';

/// Which tasks the wall shows.
enum WallTodoScope {
  /// Every list.
  all,

  /// Lists with at least one open task assigned to me, with all their tasks.
  myLists,

  /// Only my tasks, on the lists that have them.
  myTasks,
}

/// The wall's todo filter: a scope plus lists hidden by hand.
class WallTodoFilter {
  const WallTodoFilter({
    this.scope = WallTodoScope.all,
    this.hidden = const {},
  });

  final WallTodoScope scope;
  final Set<String> hidden;

  bool get isActive => scope != WallTodoScope.all || hidden.isNotEmpty;

  /// The lists and open tasks to show, in the order of [lists].
  ({List<TodoList> lists, List<TodoItem> items}) apply(
    List<TodoList> lists,
    List<TodoItem> openItems,
    String me,
  ) {
    var visible = lists.where((l) => !hidden.contains(l.id)).toList();
    var items = openItems;
    if (scope != WallTodoScope.all) {
      final mine = openItems.where((i) => i.assigneeId == me);
      final withMine = {for (final i in mine) i.listId};
      visible = visible.where((l) => withMine.contains(l.id)).toList();
      if (scope == WallTodoScope.myTasks) items = mine.toList();
    }
    final ids = {for (final l in visible) l.id};
    return (
      lists: visible,
      items: items.where((i) => ids.contains(i.listId)).toList(),
    );
  }

  WallTodoFilter copyWith({WallTodoScope? scope, Set<String>? hidden}) =>
      WallTodoFilter(scope: scope ?? this.scope, hidden: hidden ?? this.hidden);

  factory WallTodoFilter.fromJson(Map<String, dynamic> j) => WallTodoFilter(
    scope:
        WallTodoScope.values.where((s) => s.name == j['scope']).firstOrNull ??
        WallTodoScope.all,
    hidden: {...(j['hidden'] as List? ?? const []).cast<String>()},
  );

  Map<String, dynamic> toJson() => {
    'scope': scope.name,
    'hidden': hidden.toList(),
  };
}

/// The wall's todo filter, remembered per member on this device.
class WallTodoFilterPreference extends AsyncNotifier<WallTodoFilter> {
  String get _key => 'oiko.wall_todo_filter.${ref.read(currentMemberProvider)}';

  @override
  Future<WallTodoFilter> build() async {
    ref.watch(currentMemberProvider);
    final v = await DevicePrefs.get(_key);
    if (v == null) return const WallTodoFilter();
    try {
      return WallTodoFilter.fromJson(jsonDecode(v) as Map<String, dynamic>);
    } catch (_) {
      return const WallTodoFilter();
    }
  }

  Future<void> set(WallTodoFilter filter) async {
    state = AsyncData(filter);
    await DevicePrefs.set(_key, jsonEncode(filter.toJson()));
  }
}

final wallTodoFilterProvider =
    AsyncNotifierProvider<WallTodoFilterPreference, WallTodoFilter>(
      WallTodoFilterPreference.new,
    );

/// The filter button in the wall header; marked while a filter is on.
class WallTodoFilterButton extends ConsumerWidget {
  const WallTodoFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(wallTodoFilterProvider).value?.isActive ?? false;
    return IconButton(
      tooltip: context.l10n.todoWallFilter,
      isSelected: active,
      icon: const Icon(Icons.filter_list),
      selectedIcon: Badge(child: const Icon(Icons.filter_list)),
      onPressed: () => showEditorSheet<void>(
        context,
        builder: (_) => const _WallTodoFilterSheet(),
      ),
    );
  }
}

/// Changes apply at once; there is nothing to save.
class _WallTodoFilterSheet extends ConsumerWidget {
  const _WallTodoFilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final filter =
        ref.watch(wallTodoFilterProvider).value ?? const WallTodoFilter();
    final lists = ref.watch(todoListsProvider).value ?? const <TodoList>[];
    void set(WallTodoFilter f) =>
        ref.read(wallTodoFilterProvider.notifier).set(f);

    return EditorSheet(
      title: l.todoWallFilter,
      primary: TextButton(
        onPressed: filter.isActive ? () => set(const WallTodoFilter()) : null,
        child: Text(l.todoWallFilterReset),
      ),
      children: [
        RadioGroup<WallTodoScope>(
          groupValue: filter.scope,
          onChanged: (s) => set(filter.copyWith(scope: s)),
          child: Column(
            children: [
              for (final (scope, label) in [
                (WallTodoScope.all, l.todoWallScopeAll),
                (WallTodoScope.myLists, l.todoWallScopeMyLists),
                (WallTodoScope.myTasks, l.todoWallScopeMyTasks),
              ])
                RadioListTile<WallTodoScope>(
                  contentPadding: EdgeInsets.zero,
                  value: scope,
                  title: Text(label),
                ),
            ],
          ),
        ),
        const Divider(height: 24),
        Text(l.todoWallFilterLists, style: theme.textTheme.labelLarge),
        for (final list in lists)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: ColorDot(Color(list.color), size: 14),
            title: Text(list.name),
            value: !filter.hidden.contains(list.id),
            onChanged: (show) => set(
              filter.copyWith(
                hidden: show
                    ? ({...filter.hidden}..remove(list.id))
                    : {...filter.hidden, list.id},
              ),
            ),
          ),
      ],
    );
  }
}
