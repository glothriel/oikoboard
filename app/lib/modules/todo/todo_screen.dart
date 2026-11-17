import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/family.dart';
import '../../core/format.dart';
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
    // liczniki przy listach liczymy z niezrobionych zadań (widok todo.open)
    final items = ref.watch(todoOpenItemsProvider).value ?? const <TodoItem>[];
    final lists = listsAsync.value;
    if (lists == null) {
      return Center(
        child: listsAsync.hasError
            ? Text('Błąd: ${listsAsync.error}')
            : const CircularProgressIndicator(),
      );
    }

    final selectedId = ref.watch(selectedTodoListProvider);
    final selected =
        lists.where((l) => l.id == selectedId).firstOrNull ?? lists.firstOrNull;

    final pane = selected == null
        ? const Center(child: Text('Brak list — dodaj pierwszą.'))
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

int _openCount(List<TodoItem> items, String listId) =>
    items.where((i) => i.listId == listId && !i.done).length;

Future<void> _addList(BuildContext context, WidgetRef ref, int count) async {
  final name = await _askForName(context, title: 'Nowa lista');
  if (name == null) return;
  final list = await ref
      .read(todoRepositoryProvider)
      .addList(name, color: listPalette[count % listPalette.length]);
  ref.read(selectedTodoListProvider.notifier).select(list.id);
}

Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      void submit() {
        final v = controller.text.trim();
        Navigator.pop(context, v.isEmpty ? null : v);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nazwa'),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          FilledButton(onPressed: submit, child: const Text('Zapisz')),
        ],
      );
    },
  );
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
    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        for (final l in lists)
          ListTile(
            selected: l.id == selectedId,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: ColorDot(Color(l.color), size: 14),
            title: Text(l.name),
            trailing: Text('${_openCount(items, l.id)}'),
            onTap: () =>
                ref.read(selectedTodoListProvider.notifier).select(l.id),
          ),
        ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          leading: const Icon(Icons.add),
          title: const Text('Nowa lista'),
          onTap: () => _addList(context, ref, lists.length),
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
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          for (final l in lists)
            Padding(
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
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: const Text('Lista'),
            onPressed: () => _addList(context, ref, lists.length),
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

  /// Usunięte swipe'em — chowamy od razu, nie czekając na „serwer”.
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

  Future<void> _onMenu(String action) async {
    final repo = ref.read(todoRepositoryProvider);
    switch (action) {
      case 'rename':
        final name = await _askForName(
          context,
          title: 'Zmień nazwę',
          initial: widget.list.name,
        );
        if (name != null) {
          await repo.updateList(widget.list.copyWith(name: name));
        }
      case 'delete':
        ref.read(selectedTodoListProvider.notifier).select(null);
        await repo.deleteList(widget.list.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items =
        ref.watch(todoListItemsProvider(widget.list.id)).value ??
        const <TodoItem>[];
    final visible = items.where((i) => !_hidden.contains(i.id));
    final open = visible.where((i) => !i.done).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final done = visible.where((i) => i.done).toList()
      ..sort(
        (a, b) => (b.doneAt ?? b.createdAt).compareTo(a.doneAt ?? a.createdAt),
      );

    Widget tile(TodoItem i) => TodoItemTile(
      key: ValueKey(i.id),
      item: i,
      onDismissed: () {
        setState(() => _hidden.add(i.id));
        ref.read(todoRepositoryProvider).deleteItem(i.id);
      },
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            ColorDot(Color(widget.list.color), size: 14),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.list.name, style: theme.textTheme.titleLarge),
            ),
            PopupMenuButton<String>(
              onSelected: _onMenu,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Zmień nazwę')),
                PopupMenuItem(value: 'delete', child: Text('Usuń listę')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          focusNode: _focus,
          textInputAction: TextInputAction.done,
          onSubmitted: _add,
          decoration: InputDecoration(
            hintText: 'Dodaj do „${widget.list.name}”…',
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
                'Wszystko zrobione 🎉',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
        for (final i in open) tile(i),
        if (done.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            title: Text('Zrobione (${done.length})'),
            children: [for (final i in done) tile(i)],
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
          onChanged: (_) =>
              ref.read(todoRepositoryProvider).updateItem(item.toggled()),
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
            : Text(
                'termin: ${relativeDay(item.due!)}',
                style: TextStyle(
                  color: item.overdue ? theme.colorScheme.error : null,
                ),
              ),
        trailing: member == null ? null : MemberAvatar(member, radius: 14),
        onTap: () => showTodoItemEditor(context, item),
      ),
    );
  }
}

Future<void> showTodoItemEditor(BuildContext context, TodoItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TodoItemEditor(item: item),
    );

class _TodoItemEditor extends ConsumerStatefulWidget {
  const _TodoItemEditor({required this.item});
  final TodoItem item;

  @override
  ConsumerState<_TodoItemEditor> createState() => _TodoItemEditorState();
}

class _TodoItemEditorState extends ConsumerState<_TodoItemEditor> {
  late final _title = TextEditingController(text: widget.item.title);
  late String? _assignee = widget.item.assigneeId;
  late DateTime? _due = widget.item.due;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _due = picked);
  }

  void _save() {
    final title = _title.text.trim();
    ref
        .read(todoRepositoryProvider)
        .updateItem(
          widget.item.copyWith(
            title: title.isEmpty ? null : title,
            assigneeId: _assignee,
            due: _due,
          ),
        );
    Navigator.pop(context);
  }

  void _delete() {
    ref.read(todoRepositoryProvider).deleteItem(widget.item.id);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Zadanie'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 20),
          Text('Kto się tym zajmie?', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Nikt'),
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
          Row(
            children: [
              const Icon(Icons.event_outlined),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _pickDue,
                child: Text(
                  _due == null
                      ? 'Ustaw termin'
                      : 'Termin: ${relativeDay(_due!)}',
                ),
              ),
              if (_due != null)
                IconButton(
                  tooltip: 'Usuń termin',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _due = null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              TextButton.icon(
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Usuń'),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
              const Spacer(),
              FilledButton(onPressed: _save, child: const Text('Zapisz')),
            ],
          ),
        ],
      ),
    );
  }
}
