// lib/features/graph/presentation/widgets/graph_painter.dart
// CustomPainter that draws the citizen identity graph
// Nodes = citizen circles with "petal" document dots orbiting them
// Edges = colored lines (solid or dashed) between related citizens

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../domain/graph_models.dart';

class GraphPainter extends CustomPainter {
  final IdentityGraph graph;
  final String? selectedId;
  final Offset? hoverPos;

  // Scale: logical coords (0..340 x 0..300) → canvas coords
  late double scaleX, scaleY;
  static const double logicalW = 340;
  static const double logicalH = 300;
  static const double nodeRadius = 30; // ↑ was 22

  GraphPainter({
    required this.graph,
    this.selectedId,
    this.hoverPos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    scaleX = size.width / logicalW;
    scaleY = size.height / logicalH;

    _drawEdges(canvas, size);
    _drawNodes(canvas, size);
  }

  Offset _toCanvas(Offset logical) =>
      Offset(logical.dx * scaleX, logical.dy * scaleY);

  double _r(double r) => r * scaleX;

    void _drawEdges(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      final aNode = _findNode(edge.fromCitizen);
      final bNode = _findNode(edge.toCitizen);
      if (aNode == null || bNode == null) continue;

      final a = _toCanvas(aNode.position);
      final b = _toCanvas(bNode.position);

      final paint = Paint()
        ..color = edge.color.withValues(alpha: 0.45)
        ..strokeWidth = edge.edgeType == 'duplicate_of' ? 3.0 : 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      // Draw premium curved bezier lines instead of straight lines
      final path = Path();
      path.moveTo(a.dx, a.dy);
      final dist = (b.dx - a.dx).abs() * 0.5;
      final control1 = Offset(a.dx + (a.dx < b.dx ? dist : -dist), a.dy);
      final control2 = Offset(b.dx - (a.dx < b.dx ? dist : -dist), b.dy);
      path.cubicTo(control1.dx, control1.dy, control2.dx, control2.dy, b.dx, b.dy);

      if (edge.isDashed) {
        // Dashed curved logic (approximated for simplicity, fallback to generic line)
        _drawDashed(canvas, a, b, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      // Edge type label at midpoint of bezier
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: edge.edgeType == 'parent_of' ? 'parent' :
                edge.edgeType == 'spouse_of' ? 'spouse' :
                edge.edgeType == 'duplicate_of' ? '⚠ dup' : '',
          style: TextStyle(
            color: edge.color.withValues(alpha: 0.9),
            fontSize: 11 * scaleX,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, mid - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _drawNodes(Canvas canvas, Size size) {
    for (final node in graph.nodes) {
      final pos = _toCanvas(node.position);
      final r = _r(nodeRadius);
      final isSelected = node.id == selectedId;

      // Outer glow ring when selected
      if (isSelected) {
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              _nodeColor(node).withValues(alpha: 0.35),
              _nodeColor(node).withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: pos, radius: r + _r(18)))
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pos, r + _r(18), glowPaint);
      }

      // Node Shadow for 3D elevation
      final shadowPath = Path()..addOval(Rect.fromCircle(center: pos, radius: r));
      canvas.drawShadow(shadowPath, _nodeColor(node).withValues(alpha: 0.6), 12, true);

      // Node fill
      final fillPaint = Paint()
        ..color = _nodeBg(node)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, r, fillPaint);

      // Node stroke
      final strokePaint = Paint()
        ..color = isSelected ? _nodeColor(node) : _nodeColor(node).withValues(alpha: 0.4)
        ..strokeWidth = isSelected ? 3.0 : 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawCircle(pos, r, strokePaint);

      // Document petal dots orbiting the node
      final docCount = node.docs.length.clamp(1, 8);
      for (var i = 0; i < docCount; i++) {
        final angle = (i / docCount) * 2 * math.pi - math.pi / 2;
        final petalPos = pos + Offset(
          math.cos(angle) * (r + _r(14)),
          math.sin(angle) * (r + _r(14)),
        );
        // Petal circle
        canvas.drawCircle(
          petalPos, _r(6),
          Paint()
            ..color = _nodeBg(node)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          petalPos, _r(6),
          Paint()
            ..color = _nodeColor(node).withValues(alpha: 0.6)
            ..strokeWidth = 1.0
            ..style = PaintingStyle.stroke,
        );
        // Color petal by doc confidence
        // Color petal by doc confidence
        if (i < node.docs.length) {
          final doc = node.docs[i];
          final conf = doc.confidence;
          final dotColor = conf >= 85
              ? const Color(0xFF1D9E75)
              : conf >= 60
                  ? const Color(0xFFBA7517)
                  : const Color(0xFFE24B4A);
          canvas.drawCircle(
            petalPos, _r(3.5),
            Paint()..color = dotColor.withValues(alpha: 0.85),
          );

          // Show tiny initial letter for doc type
          final String initial = doc.type.isNotEmpty ? doc.type[0].toUpperCase() : '?';
          final tpDoc = TextPainter(
            text: TextSpan(
              text: initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: 6 * scaleX,
                fontWeight: FontWeight.w900,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tpDoc.paint(canvas, petalPos - Offset(tpDoc.width / 2, tpDoc.height / 2));
        }
      }

      // Tamper/fraud indicator — red dot top-right
      if (node.isFlagged) {
        final flagPos = pos + Offset(_r(nodeRadius * 0.65), -_r(nodeRadius * 0.65));
        canvas.drawCircle(flagPos, _r(6), Paint()..color = const Color(0xFFE24B4A));
        canvas.drawCircle(
          flagPos, _r(6),
          Paint()..color = Colors.white.withValues(alpha: 0.9)..strokeWidth = 1..style = PaintingStyle.stroke,
        );
      }

      // Initials text
      final tp = TextPainter(
        text: TextSpan(
          text: node.initials,
          style: TextStyle(
            color: _nodeTextColor(node),
            fontSize: 14 * scaleX,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));

      // First name below node
      final nameTp = TextPainter(
        text: TextSpan(
          text: node.firstName,
          style: TextStyle(
            color: const Color(0xFF333333),
            fontSize: 12 * scaleX,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      nameTp.paint(
        canvas,
        pos + Offset(-nameTp.width / 2, r + _r(8)),
      );
    }
  }

  // ── Hit testing: returns citizen id at canvas position ───────
  String? hitTestNode(Offset canvasPos, Size size) {
    scaleX = size.width / logicalW;
    scaleY = size.height / logicalH;
    for (final node in graph.nodes) {
      final pos = _toCanvas(node.position);
      final hitRadius = _r(nodeRadius + 14);
      if ((canvasPos - pos).distance < hitRadius) return node.id;
    }
    return null;
  }

  // ── Color helpers ─────────────────────────────────────────
  Color _nodeColor(CitizenNode n) {
    // Cycle through palette based on name hash for consistency
    final colors = [
      const Color(0xFF185FA5),
      const Color(0xFF993556),
      const Color(0xFF0F6E56),
      const Color(0xFF854F0B),
      const Color(0xFF534AB7),
      const Color(0xFF993C1D),
    ];
    return colors[n.fullName.hashCode.abs() % colors.length];
  }

  Color _nodeBg(CitizenNode n) {
    final bgs = [
      const Color(0xFFE6F1FB),
      const Color(0xFFFBEAF0),
      const Color(0xFFE1F5EE),
      const Color(0xFFFAEEDA),
      const Color(0xFFEEEDFE),
      const Color(0xFFFAECE7),
    ];
    return bgs[n.fullName.hashCode.abs() % bgs.length];
  }

  Color _nodeTextColor(CitizenNode n) {
    final txs = [
      const Color(0xFF0C447C),
      const Color(0xFF72243E),
      const Color(0xFF085041),
      const Color(0xFF633806),
      const Color(0xFF3C3489),
      const Color(0xFF712B13),
    ];
    return txs[n.fullName.hashCode.abs() % txs.length];
  }

  CitizenNode? _findNode(String id) {
    try {
      return graph.nodes.firstWhere((n) => n.id == id);
    } catch (e) {
      return null;
    }
  }

  void _drawDashed(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLen = 5.0;
    const gapLen = 4.0;
    final total = (end - start).distance;
    final dir = (end - start) / total;
    var pos = 0.0;
    var drawing = true;
    while (pos < total) {
      final nextPos = (pos + (drawing ? dashLen : gapLen)).clamp(0.0, total);
      if (drawing) {
        canvas.drawLine(
          start + dir * pos,
          start + dir * nextPos,
          paint,
        );
      }
      pos = nextPos;
      drawing = !drawing;
    }
  }

  @override
  bool shouldRepaint(GraphPainter old) =>
      old.selectedId != selectedId || old.graph != graph;
}
