import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n.dart';

/// Bare http(s) and www. links in plain text.
final _linkPattern = RegExp(r'''(?:https?://|www\.)[^\s<>"']+''');

/// Trailing punctuation that usually ends the sentence, not the link.
final _trailing = RegExp(r'''[.,;:!?)\]}'"]+$''');

/// Shorter than the reorder drag's delay (kLongPressTimeout), so holding a
/// link opens its menu while holding elsewhere in a row still drags it.
const _linkLongPress = Duration(milliseconds: 400);

typedef _Link = ({int start, int end, Uri uri});

/// Plain text (e.g. a task title) with links shown as links. A plain tap goes
/// to the parent (e.g. a row opens its editor); a link opens from its menu
/// (long press, right click) or with Ctrl/⌘+click.
class LinkText extends StatefulWidget {
  const LinkText(this.text, {super.key, this.style, this.onOpen});
  final String text;
  final TextStyle? style;

  /// Opens a link; default: outside the app.
  final void Function(Uri)? onOpen;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final _textKey = GlobalKey();
  late List<_Link> _links = _parse(widget.text);

  @override
  void didUpdateWidget(LinkText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _links = _parse(widget.text);
  }

  static List<_Link> _parse(String text) => [
    for (final m in _linkPattern.allMatches(text)) ?_link(m),
  ];

  static _Link? _link(RegExpMatch m) {
    var link = m[0]!;
    link = link.substring(
      0,
      link.length - (_trailing.firstMatch(link)?[0]?.length ?? 0),
    );
    if (link.isEmpty) return null;
    final uri = Uri.tryParse(link.startsWith('www.') ? 'https://$link' : link);
    return uri == null
        ? null
        : (start: m.start, end: m.start + link.length, uri: uri);
  }

  /// The link under a global position, if any.
  _Link? _linkAt(Offset global) {
    final p = _textKey.currentContext?.findRenderObject();
    if (p is! RenderParagraph || !p.attached) return null;
    final local = p.globalToLocal(global);
    final offset = p.getPositionForOffset(local).offset;
    for (final l in _links) {
      if (offset < l.start || offset > l.end) continue;
      final boxes = p.getBoxesForSelection(
        TextSelection(baseOffset: l.start, extentOffset: l.end),
      );
      if (boxes.any((b) => b.toRect().inflate(2).contains(local))) return l;
    }
    return null;
  }

  void _open(Uri uri) {
    final open = widget.onOpen;
    open != null
        ? open(uri)
        : launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _menu(Offset global, _Link link) async {
    final l = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final at = overlay.globalToLocal(global);
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: true,
          child: ListTile(
            leading: const Icon(Icons.open_in_new),
            title: Text(l.linkOpen),
          ),
        ),
        PopupMenuItem(
          value: false,
          child: ListTile(
            leading: const Icon(Icons.copy),
            title: Text(l.linkCopy),
          ),
        ),
      ],
    );
    switch (choice) {
      case true:
        _open(link.uri);
      case false:
        await Clipboard.setData(ClipboardData(text: link.uri.toString()));
        messenger?.showSnackBar(SnackBar(content: Text(l.linkCopied)));
      case null:
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty) return Text(widget.text, style: widget.style);
    final color = Theme.of(context).colorScheme.primary;
    final linkStyle = TextStyle(
      color: color,
      decoration: TextDecoration.underline,
      decorationColor: color,
    );
    final text = widget.text;
    final spans = <InlineSpan>[];
    var start = 0;
    for (final l in _links) {
      if (l.start > start) {
        spans.add(TextSpan(text: text.substring(start, l.start)));
      }
      spans.add(
        TextSpan(text: text.substring(l.start, l.end), style: linkStyle),
      );
      start = l.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));

    final Widget detector = RawGestureDetector(
      gestures: {
        _LinkClickRecognizer:
            GestureRecognizerFactoryWithHandlers<_LinkClickRecognizer>(
              () => _LinkClickRecognizer(_linkAt),
              (r) => r
                ..onTapUp = (d) {
                  if (_linkAt(d.globalPosition) case final l?) _open(l.uri);
                }
                ..onSecondaryTapUp = (d) {
                  if (_linkAt(d.globalPosition) case final l?) {
                    _menu(d.globalPosition, l);
                  }
                },
            ),
        _LinkLongPressRecognizer:
            GestureRecognizerFactoryWithHandlers<_LinkLongPressRecognizer>(
              () => _LinkLongPressRecognizer(_linkAt),
              (r) => r
                ..onLongPressStart = (d) {
                  if (_linkAt(d.globalPosition) case final l?) {
                    HapticFeedback.selectionClick();
                    _menu(d.globalPosition, l);
                  }
                },
            ),
      },
      child: Text.rich(
        key: _textKey,
        TextSpan(children: spans),
        style: widget.style,
      ),
    );
    if (!kIsWeb) return detector;
    // Web: the browser's own menu would cover ours.
    return MouseRegion(
      onEnter: (_) => BrowserContextMenu.disableContextMenu(),
      onExit: (_) => BrowserContextMenu.enableContextMenu(),
      child: detector,
    );
  }
}

/// Joins the gesture only for a right click, or a Ctrl/⌘+click, on a link —
/// a plain click is left to the parent.
class _LinkClickRecognizer extends TapGestureRecognizer {
  _LinkClickRecognizer(this.linkAt);
  final _Link? Function(Offset) linkAt;

  @override
  bool isPointerAllowed(PointerDownEvent event) {
    if (linkAt(event.position) == null) return false;
    final keys = HardwareKeyboard.instance;
    final modified = keys.isControlPressed || keys.isMetaPressed;
    final ok =
        event.buttons == kSecondaryButton ||
        (event.buttons == kPrimaryButton && modified);
    return ok && super.isPointerAllowed(event);
  }
}

/// A long press (touch) on a link.
class _LinkLongPressRecognizer extends LongPressGestureRecognizer {
  _LinkLongPressRecognizer(this.linkAt)
    : super(
        duration: _linkLongPress,
        supportedDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );
  final _Link? Function(Offset) linkAt;

  @override
  bool isPointerAllowed(PointerDownEvent event) =>
      linkAt(event.position) != null && super.isPointerAllowed(event);
}
