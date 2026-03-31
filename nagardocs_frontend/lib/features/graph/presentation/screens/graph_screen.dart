// lib/features/graph/presentation/screens/graph_screen.dart
// The full Identity Graph screen — Route: /graph

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/graph_painter.dart';
import '../widgets/citizen_detail_sheet.dart';
import '../../providers/graph_provider.dart';
import '../../domain/graph_models.dart';

class GraphScreen extends ConsumerStatefulWidget {
  const GraphScreen({super.key});

  @override
  ConsumerState<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends ConsumerState<GraphScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(graphProvider.notifier).loadGraph();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(graphProvider);
    final hasDuplicates = state.graph.edges.any((e) => e.edgeType == 'duplicate_of');

    return Scaffold(
      backgroundColor: Colors.transparent, // Background transparent so Container gradient shows
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.8), // Glassmorphism
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFF185FA5).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_tree_rounded,
                  color: Color(0xFF185FA5), size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Identity Graph',
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1A2E))),
                Text('Citizen relationship map',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ],
        ),
        actions: [
          if (hasDuplicates)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                icon: const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFE24B4A)),
                label: const Text('Duplicates',
                    style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFFE24B4A),
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFCEBEB),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                onPressed: () => _showDuplicatesSheet(context, state.graph),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                size: 22, color: Color(0xFF185FA5)),
            tooltip: 'Refresh',
            onPressed: () => ref.read(graphProvider.notifier).loadGraph(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.5,
            colors: [Color(0xFFEAF2FF), Color(0xFFF5F6FA), Colors.white],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: Column(
          children: [
            // Stats bar
            _StatsBar(graph: state.graph),

            // Graph canvas
            Expanded(
              child: state.isLoading
                  ? const _LoadingView()
                  : state.error != null
                      ? _ErrorView(
                          error: state.error!,
                          onRetry: () =>
                              ref.read(graphProvider.notifier).loadGraph(),
                        )
                      : state.graph.nodes.isEmpty
                          ? const _EmptyView()
                          : _GraphCanvas(
                              graph: state.graph,
                              selectedId: state.selectedCitizenId,
                              onNodeTap: (id) =>
                                  ref.read(graphProvider.notifier).selectCitizen(id),
                            ),
            ),

            // Edge legend
            const _EdgeLegend(),

            // Citizen detail sheet
            if (state.selectedCitizen != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                height: 280,
                child: CitizenDetailSheet(
                  citizen: state.selectedCitizen!,
                  onClose: () =>
                      ref.read(graphProvider.notifier).selectCitizen(null),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showDuplicatesSheet(BuildContext context, IdentityGraph graph) {
    final dups =
        graph.edges.where((e) => e.edgeType == 'duplicate_of').toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => _DuplicatesSheet(edges: dups, graph: graph),
    );
  }
}

// ── Graph canvas ──────────────────────────────────────────────
class _GraphCanvas extends StatefulWidget {
  final IdentityGraph graph;
  final String? selectedId;
  final ValueChanged<String?> onNodeTap;

  const _GraphCanvas({
    required this.graph,
    required this.selectedId,
    required this.onNodeTap,
  });

  @override
  State<_GraphCanvas> createState() => _GraphCanvasState();
}

class _GraphCanvasState extends State<_GraphCanvas> {
  final _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final painter = GraphPainter(
      graph: widget.graph,
      selectedId: widget.selectedId,
    );

    return GestureDetector(
      onTapUp: (details) {
        final box = _key.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final localPos = box.globalToLocal(details.globalPosition);
        final hit = painter.hitTestNode(localPos, box.size);
        widget.onNodeTap(hit);
      },
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: RepaintBoundary(
            child: CustomPaint(
              key: _key,
              painter: painter,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Stats bar ─────────────────────────────────────────────────
class _StatsBar extends StatelessWidget {
  final IdentityGraph graph;
  const _StatsBar({required this.graph});

  @override
  Widget build(BuildContext context) {
    final flagged = graph.nodes.where((n) => n.isFlagged).length;
    final totalDocs = graph.nodes.fold(0, (s, n) => s + n.docCount);
    final edges = graph.edges.length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _StatChip(
            icon: Icons.people_rounded,
            label: 'Citizens',
            value: '${graph.nodes.length}',
            color: const Color(0xFF185FA5),
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.description_rounded,
            label: 'Docs',
            value: '$totalDocs',
            color: const Color(0xFF0F6E56),
          ),
          const SizedBox(width: 10),
          _StatChip(
            icon: Icons.share_rounded,
            label: 'Links',
            value: '$edges',
            color: const Color(0xFF534AB7),
          ),
          if (flagged > 0) ...[
            const SizedBox(width: 10),
            _StatChip(
              icon: Icons.flag_rounded,
              label: 'Flagged',
              value: '$flagged',
              color: const Color(0xFFE24B4A),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color,
                      height: 1.1)),
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Edge legend ───────────────────────────────────────────────
class _EdgeLegend extends StatelessWidget {
  const _EdgeLegend();

  @override
  Widget build(BuildContext context) {
    const items = [
      ('Parent-Child', Color(0xFF1D9E75)),
      ('Spouse', Color(0xFF7F77DD)),
      ('Property', Color(0xFFBA7517)),
      ('Duplicate ⚠', Color(0xFFE24B4A)),
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Text('Legend:',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey)),
          const SizedBox(width: 10),
          Expanded(
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              children: items
                  .map((item) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: item.$2,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(item.$1,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF555555),
                                  fontWeight: FontWeight.w500)),
                        ],
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Duplicates sheet ──────────────────────────────────────────
class _DuplicatesSheet extends StatelessWidget {
  final List<GraphEdge> edges;
  final IdentityGraph graph;
  const _DuplicatesSheet({required this.edges, required this.graph});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFE24B4A), size: 20),
            const SizedBox(width: 8),
            const Text('Duplicate Identity Flags',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 16),
          if (edges.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('No duplicates detected ✓',
                    style: TextStyle(fontSize: 15, color: Colors.grey)),
              ),
            )
          else
            ...edges.map((e) {
              final a = _name(e.fromCitizen);
              final b = _name(e.toCitizen);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCEBEB),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: const Color(0xFFF09595), width: 0.5),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFE24B4A), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('$a  ↔  $b',
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                            'Confidence: ${(e.confidence * 100).toInt()}%',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFA32D2D))),
                      ],
                    ),
                  ),
                ]),
              );
            }),
        ],
      ),
    );
  }

  String _name(String id) {
    try {
      return graph.nodes.firstWhere((n) => n.id == id).fullName;
    } catch (e) {
      return id;
    }
  }
}

// ── Loading / Empty / Error states ───────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Color(0xFF185FA5),
            strokeWidth: 2.5,
          ),
          SizedBox(height: 16),
          Text('Building identity graph…',
              style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF185FA5).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_tree_outlined,
                  size: 56, color: Color(0xFF185FA5)),
            ),
            const SizedBox(height: 20),
            const Text('No citizens yet',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            const Text(
              'Upload Aadhaar cards, birth certificates,\nor property documents to build the graph.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: Colors.grey, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFE24B4A).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline,
                  size: 48, color: Color(0xFFE24B4A)),
            ),
            const SizedBox(height: 16),
            const Text('Failed to load graph',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E))),
            const SizedBox(height: 8),
            Text(error,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF185FA5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
