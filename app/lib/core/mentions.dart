import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'family.dart';

/// Mentions of family members in markdown (comments, descriptions).
///
/// Stored as a link to the member: `[@Anna](member:<id>)` — the server finds
/// them by the id, and the app shows the member's current name. In a text
/// field they are plain `@Anna`: [decodeMentions] turns links into that when
/// editing starts and [encodeMentions] turns it back on save, so typing
/// `@Anna` by hand mentions Anna too.
final mentionLinkPattern = RegExp(
  r'\[@([^\]\n]*)\]\(member:([0-9a-fA-F-]{36}|[\w-]+)\)',
);

/// Mention links → `@Name` (the current name; the stored one if the member
/// is gone).
String decodeMentions(String markdown, Family family) =>
    markdown.replaceAllMapped(
      mentionLinkPattern,
      (m) => '@${family.byId(m[2])?.name ?? m[1]}',
    );

/// `@Name` of a family member → a mention link. Longer names first, so
/// “@Ola K” isn't taken for “@Ola”.
String encodeMentions(String text, Family family) {
  final members = [...family.members]
    ..sort((a, b) => b.name.length.compareTo(a.name.length));
  if (members.isEmpty || !text.contains('@')) return text;
  final names = members.map((m) => RegExp.escape(m.name)).join('|');
  // Not inside a word or an existing link's text ("[@"), not followed by
  // more of a word.
  final re = RegExp(
    '(?<![\\p{L}\\p{N}_\\[])@($names)(?![\\p{L}\\p{N}_])',
    unicode: true,
    caseSensitive: false,
  );
  return text.replaceAllMapped(re, (m) {
    final name = m[1]!.toLowerCase();
    final member = members.firstWhere((x) => x.name.toLowerCase() == name);
    return '[@${member.name}](member:${member.id})';
  });
}

/// Ids of the members mentioned in [markdown].
Set<String> mentionedIds(String markdown) => {
  for (final m in mentionLinkPattern.allMatches(markdown)) m[2]!,
};

/// The `@query` being typed right before the cursor, or null.
({int start, String query})? activeMention(TextEditingValue v) {
  final sel = v.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final before = v.text.substring(0, sel.baseOffset);
  final m = RegExp(
    r'(?:^|[\s(])@([\p{L}\p{N}_]*)$',
    unicode: true,
  ).firstMatch(before);
  if (m == null) return null;
  return (start: sel.baseOffset - m[1]!.length - 1, query: m[1]!);
}

/// Members to suggest while `@…` is typed in [controller]: a row of chips;
/// tapping one completes the name. Empty when nothing is being typed.
class MentionSuggestions extends ConsumerWidget {
  const MentionSuggestions({super.key, required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final family = ref.watch(familyProvider);
    final me = ref.watch(currentMemberProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = activeMention(controller.value);
        if (active == null) return const SizedBox.shrink();
        final q = active.query.toLowerCase();
        final matches = family.members
            .where((m) => m.id != me && m.name.toLowerCase().startsWith(q))
            .toList();
        if (matches.isEmpty) return const SizedBox.shrink();
        // A tap on a chip isn't a tap outside the field and doesn't take
        // its focus, so typing goes on.
        return TextFieldTapRegion(
          child: ExcludeFocus(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  for (final m in matches)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        avatar: MemberAvatar(m, radius: 10),
                        label: Text(m.name),
                        onPressed: () => _complete(active.start, m),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _complete(int start, Member member) {
    final v = controller.value;
    final end = v.selection.baseOffset;
    final insert = '@${member.name} ';
    controller.value = TextEditingValue(
      text: v.text.replaceRange(start, end, insert),
      selection: TextSelection.collapsed(offset: start + insert.length),
    );
  }
}
