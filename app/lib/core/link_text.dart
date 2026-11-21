import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Bare http(s) and www. links in plain text.
final _linkPattern = RegExp(r'''(?:https?://|www\.)[^\s<>"']+''');

/// Trailing punctuation that usually ends the sentence, not the link.
final _trailing = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// Plain text (e.g. a task title) with links detected and tappable: they open
/// outside the app; taps elsewhere go to the parent (e.g. the row's onTap).
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (!_linkPattern.hasMatch(text)) return Text(text, style: widget.style);
    _disposeRecognizers();
    final color = Theme.of(context).colorScheme.primary;
    final spans = <InlineSpan>[];
    var start = 0;
    for (final m in _linkPattern.allMatches(text)) {
      var link = m[0]!;
      final trail = _trailing.firstMatch(link)?[0] ?? '';
      link = link.substring(0, link.length - trail.length);
      if (link.isEmpty) continue;
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      final uri = Uri.tryParse(
        link.startsWith('www.') ? 'https://$link' : link,
      );
      final r = TapGestureRecognizer()
        ..onTap = () {
          if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
        };
      _recognizers.add(r);
      spans.add(
        TextSpan(
          text: link,
          recognizer: r,
          mouseCursor: SystemMouseCursors.click,
          style: TextStyle(
            color: color,
            decoration: TextDecoration.underline,
            decorationColor: color,
          ),
        ),
      );
      start = m.start + link.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(TextSpan(children: spans), style: widget.style);
  }
}
