import 'package:material_ui/material_ui.dart';

/// A small line chart of [values] (oldest first), no dependencies.
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.values, this.compact = false});
  final List<double> values;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size.infinite,
      painter: _TrendPainter(
        values,
        colors.primary,
        colors.outlineVariant,
        colors.outline,
        compact,
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.line, this.grid, this.label, this.compact);
  final List<double> values;
  final Color line, grid, label;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final lo = values.reduce((a, b) => a < b ? a : b) - 0.5;
    final hi = values.reduce((a, b) => a > b ? a : b) + 0.5;
    final left = compact ? 0.0 : 36.0;
    final w = size.width - left;
    Offset at(int i) => Offset(
      left + w * i / (values.length - 1),
      size.height - size.height * (values[i] - lo) / (hi - lo),
    );
    if (!compact) {
      for (final v in [lo + 0.5, (lo + hi) / 2, hi - 0.5]) {
        final y = size.height - size.height * (v - lo) / (hi - lo);
        canvas.drawLine(
          Offset(left, y),
          Offset(size.width, y),
          Paint()..color = grid,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: v.toStringAsFixed(0),
            style: TextStyle(color: label, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(0, y - tp.height / 2));
      }
    }
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < values.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    if (!compact) {
      for (var i = 0; i < values.length; i++) {
        canvas.drawCircle(at(i), 3.5, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) => old.values != values;
}
