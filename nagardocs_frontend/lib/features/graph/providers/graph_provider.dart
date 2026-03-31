// lib/features/graph/providers/graph_provider.dart
// Riverpod state management for Identity Graph

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/graph_repository.dart';
import '../domain/graph_models.dart';
import 'package:flutter/material.dart';
import '../../../../core/network/dio_client.dart';
import 'dart:math' as math;

// ── Repository provider ───────────────────────────────────────
// Wire this to your existing dioProvider
final graphRepositoryProvider = Provider<GraphRepository>((ref) {
  final dio = ref.watch(dioProvider); // your existing dio provider
  return GraphRepository(dio);
});

// ── Graph state ───────────────────────────────────────────────
class GraphState {
  final IdentityGraph graph;
  final bool isLoading;
  final String? error;
  final String? selectedCitizenId;

  const GraphState({
    required this.graph,
    this.isLoading = false,
    this.error,
    this.selectedCitizenId,
  });

  GraphState copyWith({
    IdentityGraph? graph,
    bool? isLoading,
    String? error,
    String? selectedCitizenId,
  }) =>
      GraphState(
        graph: graph ?? this.graph,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        selectedCitizenId: selectedCitizenId ?? this.selectedCitizenId,
      );

  CitizenNode? get selectedCitizen {
    if (selectedCitizenId == null) return null;
    try {
      return graph.nodes.firstWhere((n) => n.id == selectedCitizenId);
    } catch (_) {
      return null;
    }
  }
}

// ── Graph notifier ────────────────────────────────────────────
class GraphNotifier extends Notifier<GraphState> {
  @override
  GraphState build() {
    return GraphState(graph: IdentityGraph.empty());
  }

  GraphRepository get _repo => ref.read(graphRepositoryProvider);

  Future<void> loadGraph() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final graph = await _repo.getDepartmentGraph();
      _assignPositions(graph);
      state = state.copyWith(graph: graph, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void selectCitizen(String? id) {
    state = state.copyWith(selectedCitizenId: id);
  }

  Future<void> reprocessDocument(String docId) async {
    await _repo.reprocessDocument(docId);
    await loadGraph(); // refresh
  }

  // ── Force-directed layout ─────────────────────────────────
  // Assigns x/y positions to nodes using a simple spring algorithm
  void _assignPositions(IdentityGraph graph, {Size size = const Size(340, 300)}) {
    final n = graph.nodes.length;
    if (n == 0) return;

    final rng = math.Random(42); // fixed seed = stable layout
    final W = size.width, H = size.height;
    final cx = W / 2, cy = H / 2;
    final radius = math.min(W, H) * 0.38;

    // Initial positions: circle
    for (var i = 0; i < n; i++) {
      final angle = (i / n) * 2 * math.pi - math.pi / 2;
      graph.nodes[i].position = Offset(
        cx + math.cos(angle) * radius * (0.7 + rng.nextDouble() * 0.3),
        cy + math.sin(angle) * radius * (0.7 + rng.nextDouble() * 0.3),
      );
    }

    // Spring iterations
    const iterations = 80;
    const k = 60.0;   // spring constant
    const repel = 2800.0;

    for (var iter = 0; iter < iterations; iter++) {
      final forces = List.filled(n, Offset.zero);

      // Repulsion between all pairs
      for (var i = 0; i < n; i++) {
        for (var j = i + 1; j < n; j++) {
          final delta = graph.nodes[i].position - graph.nodes[j].position;
          final dist = delta.distance.clamp(1.0, 400.0);
          final force = delta / dist * (repel / (dist * dist));
          forces[i] = forces[i] + force;
          forces[j] = forces[j] - force;
        }
      }

      // Attraction along edges
      final nodeIndex = {for (var i = 0; i < n; i++) graph.nodes[i].id: i};
      for (final edge in graph.edges) {
        final ai = nodeIndex[edge.fromCitizen];
        final bi = nodeIndex[edge.toCitizen];
        if (ai == null || bi == null) continue;
        final delta = graph.nodes[bi].position - graph.nodes[ai].position;
        final dist = delta.distance.clamp(1.0, 400.0);
        final force = delta / dist * (dist / k);
        forces[ai] = forces[ai] + force;
        forces[bi] = forces[bi] - force;
      }

      // Apply forces (damped)
      final damp = 0.1 * (1 - iter / iterations);
      for (var i = 0; i < n; i++) {
        var pos = graph.nodes[i].position + forces[i] * damp;
        // Keep within bounds with padding
        pos = Offset(
          pos.dx.clamp(40.0, W - 40.0),
          pos.dy.clamp(40.0, H - 40.0),
        );
        graph.nodes[i].position = pos;
      }
    }
  }
}

// ── Provider ──────────────────────────────────────────────────
final graphProvider =
    NotifierProvider<GraphNotifier, GraphState>(GraphNotifier.new);
