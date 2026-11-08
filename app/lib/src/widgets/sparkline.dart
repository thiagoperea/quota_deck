import 'package:flutter/material.dart';

import '../theme.dart';

/// Sparkline simples de percentual (0–100), sem animações.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 54,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = QdPalette.of(context);
    final lineColor = color ?? palette.green;
    if (values.isEmpty) {
      return SizedBox(
        height: height,
        width: double.infinity,
        child: Center(
          child: Text(
            'Sem amostras suficientes',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: palette.dim),
          ),
        ),
      );
    }

    return Semantics(
      label: 'Tendência de uso nas últimas horas',
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparklinePainter(
            values: values,
            color: lineColor,
            guideColor: palette.yellow.withValues(alpha: 0.28),
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.guideColor,
  });

  final List<double> values;
  final Color color;
  final Color guideColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final width = size.width;
    final height = size.height;
    const topPadding = 3.0;
    final drawHeight = height - topPadding * 2;

    double yFor(double value) {
      final clamped = value.clamp(0.0, 100.0).toDouble();
      return topPadding + drawHeight * (1 - clamped / 100);
    }

    final guidePaint = Paint()
      ..color = guideColor
      ..strokeWidth = 1;
    final guideY = yFor(80);
    canvas.drawLine(Offset(0, guideY), Offset(width, guideY), guidePaint);

    final points = <Offset>[];
    if (values.length == 1) {
      points.add(Offset(width, yFor(values.first)));
    } else {
      final step = width / (values.length - 1);
      for (var i = 0; i < values.length; i++) {
        points.add(Offset(i * step, yFor(values[i])));
      }
    }

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final midX = (previous.dx + current.dx) / 2;
      line.cubicTo(midX, previous.dy, midX, current.dy, current.dx, current.dy);
    }

    final area = Path.from(line)
      ..lineTo(points.last.dx, height)
      ..lineTo(points.first.dx, height)
      ..close();
    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.28), color.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(area, areaPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);

    final dotPaint = Paint()..color = color;
    canvas.drawCircle(points.last, 3, dotPaint);
    canvas.drawCircle(
      points.last,
      5.5,
      Paint()..color = color.withValues(alpha: 0.2),
    );
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.color != color ||
      oldDelegate.guideColor != guideColor;
}
