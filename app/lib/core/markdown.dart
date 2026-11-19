import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'family.dart';
import 'l10n.dart';
import 'mentions.dart';

/// Rendered markdown (descriptions, comments); links open outside the app and
/// mentions show as the member's current name.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key});
  final String data;

  /// flutter_markdown_plus reads `package:flutter/material.dart`'s Theme, which
  /// this app (on material_ui) doesn't provide — so its defaults are always the
  /// light Material theme. Build the whole sheet from the app's theme instead.
  static MarkdownStyleSheet _styleSheet(ThemeData theme) {
    final t = theme.textTheme;
    final c = theme.colorScheme;
    final body = t.bodyMedium!.copyWith(color: c.onSurface);
    final mono = body.copyWith(
      fontFamily: 'monospace',
      fontSize: body.fontSize! * 0.9,
    );
    final rounded = BoxDecoration(
      color: c.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    );
    return MarkdownStyleSheet(
      a: body.copyWith(
        color: c.primary,
        decoration: TextDecoration.underline,
        decorationColor: c.primary,
      ),
      p: body,
      pPadding: EdgeInsets.zero,
      code: mono.copyWith(backgroundColor: c.surfaceContainerHighest),
      h1: t.titleLarge!.copyWith(color: c.onSurface),
      h1Padding: EdgeInsets.zero,
      h2: t.titleMedium!.copyWith(color: c.onSurface),
      h2Padding: EdgeInsets.zero,
      h3: t.titleSmall!.copyWith(color: c.onSurface),
      h3Padding: EdgeInsets.zero,
      h4: t.titleSmall!.copyWith(color: c.onSurface),
      h4Padding: EdgeInsets.zero,
      h5: t.titleSmall!.copyWith(color: c.onSurface),
      h5Padding: EdgeInsets.zero,
      h6: t.titleSmall!.copyWith(color: c.onSurface),
      h6Padding: EdgeInsets.zero,
      em: const TextStyle(fontStyle: FontStyle.italic),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      del: const TextStyle(decoration: TextDecoration.lineThrough),
      blockquote: body.copyWith(color: c.onSurfaceVariant),
      img: body,
      checkbox: body.copyWith(color: c.primary),
      blockSpacing: 8,
      listIndent: 24,
      listBullet: body,
      listBulletPadding: const EdgeInsets.only(right: 4),
      tableHead: const TextStyle(fontWeight: FontWeight.w600),
      tableBody: body,
      tableHeadAlign: TextAlign.center,
      tablePadding: const EdgeInsets.only(bottom: 4),
      tableBorder: TableBorder.all(color: c.outlineVariant),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tableCellsDecoration: const BoxDecoration(),
      tableVerticalAlignment: TableCellVerticalAlignment.middle,
      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.outlineVariant, width: 3)),
      ),
      codeblockPadding: const EdgeInsets.all(8),
      codeblockDecoration: rounded,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.outlineVariant)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: data,
    softLineBreak: true,
    styleSheet: _styleSheet(Theme.of(context)),
    inlineSyntaxes: [_MentionSyntax()],
    builders: {'mention': _MentionBuilder()},
    onTapLink: (_, href, _) {
      final uri = href == null ? null : Uri.tryParse(href);
      if (uri != null && uri.scheme != 'member') {
        launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    },
  );
}

/// `[@Name](member:<id>)` → a `mention` element (before the link syntax).
class _MentionSyntax extends md.InlineSyntax {
  _MentionSyntax() : super(mentionLinkPattern.pattern);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.text('mention', match[1]!)..attributes['id'] = match[2]!,
    );
    return true;
  }
}

class _MentionBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final name =
        familyOf(context).byId(element.attributes['id'])?.name ??
        element.textContent;
    return Text.rich(
      TextSpan(
        text: '@$name',
        style: (parentStyle ?? const TextStyle()).copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A multi-line markdown field with a small edit / preview toggle. Mentions
/// are `@Name` in [controller] (see [decodeMentions]); typing `@` suggests
/// members.
class MarkdownField extends StatefulWidget {
  const MarkdownField({
    super.key,
    required this.controller,
    this.label,
    this.maxLines = 10,
  });
  final TextEditingController controller;
  final String? label;
  final int maxLines;

  @override
  State<MarkdownField> createState() => _MarkdownFieldState();
}

class _MarkdownFieldState extends State<MarkdownField> {
  bool _preview = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (widget.label != null)
              Expanded(
                child: Text(widget.label!, style: theme.textTheme.labelLarge),
              )
            else
              const Spacer(),
            IconButton(
              tooltip: _preview ? l.markdownEdit : l.markdownPreview,
              visualDensity: VisualDensity.compact,
              iconSize: 18,
              color: theme.colorScheme.outline,
              isSelected: _preview,
              icon: const Icon(Icons.visibility_outlined),
              selectedIcon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _preview = !_preview),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (_preview)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.controller.text.trim().isEmpty
                ? Text(
                    l.markdownNothing,
                    style: TextStyle(color: theme.colorScheme.outline),
                  )
                : MarkdownText(
                    encodeMentions(widget.controller.text, familyOf(context)),
                  ),
          )
        else ...[
          TextField(
            controller: widget.controller,
            minLines: 3,
            maxLines: widget.maxLines,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          MentionSuggestions(controller: widget.controller),
        ],
      ],
    );
  }
}
