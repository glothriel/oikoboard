import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/format.dart';
import '../../core/l10n.dart';
import '../../core/markdown.dart';
import '../../core/mentions.dart';
import '../../core/undo_delete.dart';
import '../../core/widgets.dart';
import 'models.dart';
import 'repository.dart';

const listPalette = [
  0xFF26A69A,
  0xFF5C6BC0,
  0xFFFFA726,
  0xFFEC407A,
  0xFF8D6E63,
  0xFF42A5F5,
];

class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listsAsync = ref.watch(todoListsProvider);
    // list counters count the open (not done) tasks (the todo.open view)
    final items = ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[];
    final lists = listsAsync.value;
    if (lists == null) {
      return Center(
        child: listsAsync.hasError
            ? Text(context.l10n.todoError('${listsAsync.error}'))
            : const CircularProgressIndicator(),
      );
    }

    final selectedId = ref.watch(selectedTodoListProvider);
    final selected =
        lists.where((l) => l.id == selectedId).firstOrNull ?? lists.firstOrNull;

    final pane = selected == null
        ? Center(child: Text(context.l10n.todoNoLists))
        : TodoItemsPane(key: ValueKey(selected.id), list: selected);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 260,
                child: _ListsPanel(
                  lists: lists,
                  items: items,
                  selectedId: selected?.id,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: pane),
            ],
          );
        }
        return Column(
          children: [
            _ListChips(lists: lists, items: items, selectedId: selected?.id),
            Expanded(child: pane),
          ],
        );
      },
    );
  }
}

/// Date picker for a due date.
Future<DateTime?> pickDueDate(BuildContext context, DateTime? initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial ?? now,
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
}

/// Ticks or unticks [item], saving the fields of [edited] too. Ticking shows
/// a snackbar with Undo for 3 s.
void toggleTodoDone(
  BuildContext context,
  WidgetRef ref,
  TodoItem item, {
  TodoItem? edited,
}) {
  final repo = ref.read(todoRepositoryProvider);
  final next = (edited ?? item).toggled();
  repo.updateItem(item, next);
  if (!next.done) return;
  final l = context.l10n;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        persist: false, // a snackbar with an action stays put by default
        content: Text(l.todoMarkedDone(next.title)),
        action: SnackBarAction(
          label: l.commonUndo,
          onPressed: () =>
              repo.updateItem(next, next.copyWith(done: false, doneAt: null)),
        ),
      ),
    );
}

/// Time picker for a due time.
Future<TimeOfDay?> pickDueTime(BuildContext context, TimeOfDay? initial) =>
    showTimePicker(
      context: context,
      initialTime: initial ?? const TimeOfDay(hour: 9, minute: 0),
    );

/// The due date, with its time if it has one: “Today, 17:30”.
String dueText(BuildContext context, DateTime due, [TimeOfDay? time]) {
  final l = context.l10n;
  final day = relativeDay(l, due);
  return time == null ? day : l.todoDayAt(day, time.format(context));
}

/// “Due: Fri, 20 Nov” in the error color when overdue; for lists and tasks.
class DueLabel extends StatelessWidget {
  const DueLabel(
    this.due, {
    super.key,
    required this.overdue,
    this.time,
    this.style,
  });
  final DateTime due;
  final TimeOfDay? time;
  final bool overdue;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Text(
    context.l10n.todoDue(dueText(context, due, time)),
    style: (style ?? const TextStyle()).copyWith(
      color: overdue ? Theme.of(context).colorScheme.error : null,
    ),
  );
}

int _openCount(List<TodoItem> items, String listId) =>
    items.where((i) => i.listId == listId && !i.done).length;

Future<void> _addList(BuildContext context, WidgetRef ref, int count) async {
  final id = await showTodoListEditor(
    context,
    color: listPalette[count % listPalette.length],
  );
  if (id != null) ref.read(selectedTodoListProvider.notifier).select(id);
}

/// The list editor side sheet: name, description, color, due date and delete.
/// Creates a list when [list] is null; returns the id of the saved list.
Future<String?> showTodoListEditor(
  BuildContext context, {
  TodoList? list,
  int color = 0xFF26A69A,
}) => showEditorSheet<String>(
  context,
  builder: (_) => _TodoListEditor(list: list, color: color),
);

class _TodoListEditor extends ConsumerStatefulWidget {
  const _TodoListEditor({required this.list, required this.color});
  final TodoList? list;
  final int color;

  @override
  ConsumerState<_TodoListEditor> createState() => _TodoListEditorState();
}

class _TodoListEditorState extends ConsumerState<_TodoListEditor> {
  late final _name = TextEditingController(text: widget.list?.name);
  late final _description = TextEditingController(
    text: decodeMentions(
      widget.list?.description ?? '',
      ref.read(familyProvider),
    ),
  );
  late int _color = widget.list?.color ?? widget.color;
  late DateTime? _due = widget.list?.due;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final picked = await pickDueDate(context, _due);
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    final description = encodeMentions(
      _description.text.trim(),
      ref.read(familyProvider),
    );
    final repo = ref.read(todoRepositoryProvider);
    final list = widget.list;
    final String id;
    if (list == null) {
      id = (await repo.addList(
        name,
        color: _color,
        description: description,
        due: _due,
      )).id;
    } else {
      id = list.id;
      await repo.updateList(
        list,
        list.copyWith(
          name: name,
          description: description,
          color: _color,
          due: _due,
        ),
      );
    }
    if (mounted) Navigator.pop(context, id);
  }

  void _delete() {
    final list = widget.list!;
    final repo = ref.read(todoRepositoryProvider);
    final selected = ref.read(selectedTodoListProvider.notifier);
    selected.select(null);
    deleteWithUndo(
      context,
      key: todoListKey(list.id),
      message: context.l10n.commonDeleted(list.name),
      commit: () => repo.deleteList(list),
      onUndo: () => selected.select(list.id),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final colors = {...listPalette, _color};
    return EditorSheet(
      title: widget.list == null ? l.todoNewList : l.todoEditList,
      actions: [
        if (widget.list != null)
          IconButton(
            tooltip: l.todoDeleteList,
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
      ],
      primary: ListenableBuilder(
        listenable: _name,
        builder: (context, _) => FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _save,
          child: Text(l.commonSave),
        ),
      ),
      children: [
        TextField(
          controller: _name,
          autofocus: widget.list == null,
          decoration: InputDecoration(labelText: l.todoName),
        ),
        const SizedBox(height: 20),
        Text(l.todoColor, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in colors)
              InkResponse(
                onTap: () => setState(() => _color = c),
                radius: 22,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: c == _color
                        ? Border.all(
                            color: theme.colorScheme.onSurface,
                            width: 3,
                          )
                        : null,
                  ),
                  child: c == _color
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _DueRow(
          due: _due,
          onPick: _pickDue,
          onClear: () => setState(() => _due = null),
        ),
        const SizedBox(height: 16),
        MarkdownField(controller: _description, label: l.todoDescription),
      ],
    );
  }
}

/// "Set due date" / "Due: …" with a clear button; for lists and tasks. With
/// [onPickTime] (tasks), a set date can also get a time.
class _DueRow extends StatelessWidget {
  const _DueRow({
    required this.due,
    required this.onPick,
    required this.onClear,
    this.time,
    this.onPickTime,
    this.onClearTime,
  });
  final DateTime? due;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final TimeOfDay? time;
  final VoidCallback? onPickTime;
  final VoidCallback? onClearTime;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Icon(Icons.event_outlined),
        const SizedBox(width: 8),
        TextButton(
          onPressed: onPick,
          child: Text(
            due == null ? l.todoSetDue : l.todoDueLabel(relativeDay(l, due!)),
          ),
        ),
        if (due != null)
          IconButton(
            tooltip: l.todoRemoveDue,
            icon: const Icon(Icons.close),
            onPressed: onClear,
          ),
        if (due != null && onPickTime != null) ...[
          TextButton.icon(
            onPressed: onPickTime,
            icon: const Icon(Icons.schedule),
            label: Text(time == null ? l.todoSetTime : time!.format(context)),
          ),
          if (time != null)
            IconButton(
              tooltip: l.todoRemoveTime,
              icon: const Icon(Icons.close),
              onPressed: onClearTime,
            ),
        ],
      ],
    );
  }
}

class _ListsPanel extends ConsumerWidget {
  const _ListsPanel({
    required this.lists,
    required this.items,
    required this.selectedId,
  });

  final List<TodoList> lists;
  final List<TodoItem> items;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ReorderableListView(
      padding: const EdgeInsets.all(8),
      buildDefaultDragHandles: false,
      onReorderItem: (from, to) =>
          ref.read(todoListOrderProvider.notifier).move(lists, from, to),
      footer: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.add),
        title: Text(context.l10n.todoNewList),
        onTap: () => _addList(context, ref, lists.length),
      ),
      children: [
        for (final (index, l) in lists.indexed)
          ReorderableDelayedDragStartListener(
            key: ValueKey(l.id),
            index: index,
            child: ListTile(
              selected: l.id == selectedId,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              leading: ColorDot(Color(l.color), size: 14),
              title: Text(l.name),
              subtitle: l.due == null
                  ? null
                  : DueLabel(l.due!, overdue: l.overdue),
              trailing: Text('${_openCount(items, l.id)}'),
              onTap: () =>
                  ref.read(selectedTodoListProvider.notifier).select(l.id),
            ),
          ),
      ],
    );
  }
}

class _ListChips extends ConsumerWidget {
  const _ListChips({
    required this.lists,
    required this.items,
    required this.selectedId,
  });

  final List<TodoList> lists;
  final List<TodoItem> items;
  final String? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 56,
      child: ReorderableListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        buildDefaultDragHandles: false,
        onReorderItem: (from, to) =>
            ref.read(todoListOrderProvider.notifier).move(lists, from, to),
        footer: ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: Text(context.l10n.todoListChip),
          onPressed: () => _addList(context, ref, lists.length),
        ),
        children: [
          for (final (index, l) in lists.indexed)
            ReorderableDelayedDragStartListener(
              key: ValueKey(l.id),
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: ColorDot(Color(l.color)),
                  label: Text('${l.name} · ${_openCount(items, l.id)}'),
                  selected: l.id == selectedId,
                  showCheckmark: false,
                  onSelected: (_) =>
                      ref.read(selectedTodoListProvider.notifier).select(l.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class TodoItemsPane extends ConsumerStatefulWidget {
  const TodoItemsPane({super.key, required this.list});

  final TodoList list;

  @override
  ConsumerState<TodoItemsPane> createState() => _TodoItemsPaneState();
}

class _TodoItemsPaneState extends ConsumerState<TodoItemsPane> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  /// Swiped away — hidden right away, without waiting for the server.
  final _hidden = <String>{};

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add(String text) async {
    final title = text.trim();
    if (title.isEmpty) return;
    _controller.clear();
    _focus.requestFocus();
    await ref.read(todoRepositoryProvider).addItem(widget.list.id, title);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final items =
        ref.watch(todoListItemsProvider(widget.list.id)).value ??
        const <TodoItem>[];
    final visible = items.where((i) => !_hidden.contains(i.id));
    final open = visible.where((i) => !i.done).toList()
      ..sort(TodoItem.byPosition);
    final done = visible.where((i) => i.done).toList()
      ..sort(
        (a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt),
      );

    Widget tile(TodoItem i) => TodoItemTile(
      key: ValueKey(i.id),
      item: i,
      onDismissed: () {
        // Hidden in this frame already: a dismissed tile must leave the tree.
        setState(() => _hidden.add(i.id));
        final repo = ref.read(todoRepositoryProvider);
        deleteWithUndo(
          context,
          key: todoItemKey(i.id),
          message: context.l10n.commonDeleted(i.title),
          commit: () => repo.deleteItem(i),
          onUndo: () {
            if (mounted) setState(() => _hidden.remove(i.id));
          },
        );
      },
    );

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          sliver: SliverList.list(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => showTodoListEditor(context, list: widget.list),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      ColorDot(Color(widget.list.color), size: 14),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.list.name,
                              style: theme.textTheme.titleLarge,
                            ),
                            if (widget.list.due != null)
                              DueLabel(
                                widget.list.due!,
                                overdue: widget.list.overdue && open.isNotEmpty,
                                style: theme.textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: l.todoEditList,
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () =>
                            showTodoListEditor(context, list: widget.list),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.list.description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 0, 4),
                  child: MarkdownText(widget.list.description),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.done,
                onSubmitted: _add,
                decoration: InputDecoration(
                  hintText: l.todoAddTo(widget.list.name),
                  prefixIcon: const Icon(Icons.add),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (open.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      l.todoAllDone,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Open tasks: long-press and drag to reorder (for everyone).
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverReorderableList(
            itemCount: open.length,
            onReorderItem: (from, to) =>
                moveTodoItem(ref.read(todoRepositoryProvider), open, from, to),
            proxyDecorator: (child, _, _) => Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: child,
            ),
            itemBuilder: (context, index) =>
                ReorderableDelayedDragStartListener(
                  key: ValueKey(open[index].id),
                  index: index,
                  child: tile(open[index]),
                ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverList.list(
            children: [
              if (done.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  shape: const Border(),
                  title: Text(l.todoDoneSection(done.length)),
                  children: [for (final i in done) tile(i)],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class TodoItemTile extends ConsumerWidget {
  const TodoItemTile({
    super.key,
    required this.item,
    required this.onDismissed,
  });

  final TodoItem item;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final member = ref.watch(familyProvider).byId(item.assigneeId);
    return Dismissible(
      key: ValueKey('dismiss-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: theme.colorScheme.errorContainer,
        child: Icon(
          Icons.delete_outline,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Checkbox(
          value: item.done,
          onChanged: (_) => toggleTodoDone(context, ref, item),
        ),
        title: Text(
          item.title,
          style: item.done
              ? TextStyle(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.outline,
                )
              : null,
        ),
        subtitle: item.due == null
            ? null
            : DueLabel(item.due!, time: item.dueTime, overdue: item.overdue),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Tooltip(
                  message: context.l10n.todoHasDescription,
                  child: Icon(
                    Icons.notes,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            if (member != null) MemberAvatar(member, radius: 14),
          ],
        ),
        onTap: () => showTodoItemEditor(context, item),
      ),
    );
  }
}

Future<void> showTodoItemEditor(BuildContext context, TodoItem item) =>
    showEditorSheet<void>(context, builder: (_) => _TodoItemEditor(item: item));

/// A task's comments as a separate view: the thread and a field at the bottom.
Future<void> showTodoComments(BuildContext context, TodoItem item) =>
    showSideSheet<void>(
      context,
      builder: (context) => SideSheetScaffold(
        title: context.l10n.todoCommentsOf(item.title),
        bottom: TodoCommentComposer(itemId: item.id),
        children: [TodoCommentList(itemId: item.id)],
      ),
    );

class _TodoItemEditor extends ConsumerStatefulWidget {
  const _TodoItemEditor({required this.item});
  final TodoItem item;

  @override
  ConsumerState<_TodoItemEditor> createState() => _TodoItemEditorState();
}

class _TodoItemEditorState extends ConsumerState<_TodoItemEditor> {
  late final _title = TextEditingController(text: widget.item.title);
  late final _description = TextEditingController(
    text: decodeMentions(widget.item.description, ref.read(familyProvider)),
  );
  late String? _assignee = widget.item.assigneeId;
  late DateTime? _due = widget.item.due;
  late TimeOfDay? _dueTime = widget.item.dueTime;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final picked = await pickDueDate(context, _due);
    if (picked != null) setState(() => _due = picked);
  }

  Future<void> _pickDueTime() async {
    final picked = await pickDueTime(context, _dueTime);
    if (picked != null) setState(() => _dueTime = picked);
  }

  TodoItem _edited() {
    final title = _title.text.trim();
    return widget.item.copyWith(
      title: title.isEmpty ? null : title,
      description: encodeMentions(
        _description.text.trim(),
        ref.read(familyProvider),
      ),
      assigneeId: _assignee,
      due: _due,
      dueTime: _due == null ? null : _dueTime,
    );
  }

  void _save() {
    ref.read(todoRepositoryProvider).updateItem(widget.item, _edited());
    Navigator.pop(context);
  }

  void _delete() {
    final item = widget.item;
    final repo = ref.read(todoRepositoryProvider);
    deleteWithUndo(
      context,
      key: todoItemKey(item.id),
      message: context.l10n.commonDeleted(item.title),
      commit: () => repo.deleteItem(item),
    );
    Navigator.pop(context);
  }

  /// Saves the edits, ticks (or unticks) the task and closes the sheet.
  void _toggleDone() {
    toggleTodoDone(context, ref, widget.item, edited: _edited());
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final comments =
        ref.watch(todoCommentsProvider(widget.item.id)).value?.length ?? 0;
    return EditorSheet(
      title: l.todoTask,
      actions: [
        IconButton(
          tooltip: l.commonDelete,
          icon: const Icon(Icons.delete_outline),
          onPressed: _delete,
        ),
        IconButton(
          tooltip: l.todoComments,
          onPressed: () => showTodoComments(context, widget.item),
          icon: Badge.count(
            count: comments,
            isLabelVisible: comments > 0,
            child: const Icon(Icons.forum_outlined),
          ),
        ),
      ],
      primary: FilledButton(onPressed: _save, child: Text(l.commonSave)),
      children: [
        Row(
          children: [
            // Ticking here is the same as on the list: done, sheet closed.
            Tooltip(
              message: widget.item.done ? l.todoReopen : l.todoMarkDone,
              child: Checkbox(
                value: widget.item.done,
                onChanged: (_) => _toggleDone(),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _title,
                decoration: InputDecoration(labelText: l.todoTask),
                onSubmitted: (_) => _save(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(l.todoWhoDoesIt, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: Text(l.commonNobody),
              selected: _assignee == null,
              onSelected: (_) => setState(() => _assignee = null),
            ),
            for (final m in ref.watch(familyProvider).members)
              ChoiceChip(
                avatar: MemberAvatar(m, radius: 10),
                label: Text(m.name),
                selected: _assignee == m.id,
                showCheckmark: false,
                onSelected: (_) => setState(() => _assignee = m.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        _DueRow(
          due: _due,
          onPick: _pickDue,
          onClear: () => setState(() {
            _due = null;
            _dueTime = null;
          }),
          time: _dueTime,
          onPickTime: _pickDueTime,
          onClearTime: () => setState(() => _dueTime = null),
        ),
        const SizedBox(height: 16),
        MarkdownField(controller: _description, label: l.todoDescription),
      ],
    );
  }
}

/// A task's comment thread: author, time and text.
class TodoCommentList extends ConsumerWidget {
  const TodoCommentList({super.key, required this.itemId});
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final comments =
        ref.watch(todoCommentsProvider(itemId)).value ?? const <TodoComment>[];
    if (comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            l.todoNoComments,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
      );
    }
    final family = ref.watch(familyProvider);
    final me = ref.watch(currentMemberProvider);

    String when(DateTime t) {
      final local = t.toLocal();
      return isSameDay(local, DateTime.now())
          ? hm(local)
          : '${relativeDay(l, local)} ${hm(local)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final c in comments)
          ListTile(
            key: ValueKey(c.id),
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: family.byId(c.authorId) == null
                ? const CircleAvatar(
                    radius: 14,
                    child: Icon(Icons.person_outline, size: 16),
                  )
                : MemberAvatar(family.byId(c.authorId)!, radius: 14),
            title: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text:
                        family.byId(c.authorId)?.name ??
                        l.todoCommentFormerMember,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  ${when(c.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            subtitle: MarkdownText(c.body),
            trailing: c.authorId == me
                ? IconButton(
                    tooltip: l.todoCommentDelete,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      final repo = ref.read(todoRepositoryProvider);
                      deleteWithUndo(
                        context,
                        key: todoCommentKey(c.id),
                        message: l.todoCommentDeleted,
                        commit: () => repo.deleteComment(c),
                      );
                    },
                  )
                : null,
          ),
      ],
    );
  }
}

/// The multi-line comment field pinned under a task: Enter adds a line,
/// the send button (or Ctrl/Cmd+Enter) posts it.
class TodoCommentComposer extends ConsumerStatefulWidget {
  const TodoCommentComposer({super.key, required this.itemId});
  final String itemId;

  @override
  ConsumerState<TodoCommentComposer> createState() =>
      _TodoCommentComposerState();
}

class _TodoCommentComposerState extends ConsumerState<TodoCommentComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final body = _controller.text.trim();
    if (body.isEmpty) return;
    _controller.clear();
    ref
        .read(todoRepositoryProvider)
        .addComment(
          widget.itemId,
          encodeMentions(body, ref.read(familyProvider)),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter, control: true):
                  _send,
              const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                  _send,
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MentionSuggestions(controller: _controller),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: l.todoCommentHint,
                          isDense: true,
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _controller,
                      builder: (context, _) => IconButton(
                        tooltip: l.todoCommentSend,
                        icon: const Icon(Icons.send),
                        onPressed: _controller.text.trim().isEmpty
                            ? null
                            : _send,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
