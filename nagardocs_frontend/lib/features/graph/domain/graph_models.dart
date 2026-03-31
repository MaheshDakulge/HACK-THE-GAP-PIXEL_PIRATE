// lib/features/graph/domain/graph_models.dart
// Data models for the Citizen Identity Graph

import 'package:flutter/material.dart';

// ── Document linked to a citizen ─────────────────────────────
class CitizenDocument {
  final String documentId;
  final String type;
  final String value;
  final int confidence;
  final bool isTampered;
  final String filename;

  const CitizenDocument({
    required this.documentId,
    required this.type,
    required this.value,
    required this.confidence,
    required this.isTampered,
    required this.filename,
  });

  factory CitizenDocument.fromJson(Map<String, dynamic> j) => CitizenDocument(
        documentId: j['document_id'] ?? '',
        type: j['type'] ?? 'Unknown',
        value: j['value'] ?? '',
        confidence: (j['confidence'] as num?)?.toInt() ?? 0,
        isTampered: j['is_tampered'] ?? false,
        filename: j['filename'] ?? '',
      );

  Color get confidenceColor {
    if (confidence >= 85) return const Color(0xFF1D9E75);
    if (confidence >= 60) return const Color(0xFFBA7517);
    return const Color(0xFFE24B4A);
  }
}

// ── Citizen node ──────────────────────────────────────────────
class CitizenNode {
  final String id;
  final String fullName;
  final String? dob;
  final String? uidNumber;
  final bool isFlagged;
  final int docCount;
  final List<CitizenDocument> docs;

  // Layout position (assigned by graph layout algorithm)
  Offset position;

  CitizenNode({
    required this.id,
    required this.fullName,
    this.dob,
    this.uidNumber,
    required this.isFlagged,
    required this.docCount,
    required this.docs,
    this.position = Offset.zero,
  });

  String get initials {
    final parts = fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return fullName.substring(0, 2).toUpperCase();
  }

  String get firstName => fullName.split(' ').first;

  factory CitizenNode.fromJson(Map<String, dynamic> j) => CitizenNode(
        id: j['id'],
        fullName: j['full_name'] ?? 'Unknown',
        dob: j['dob'],
        uidNumber: j['uid_number'],
        isFlagged: j['is_flagged'] ?? false,
        docCount: j['doc_count'] ?? 0,
        docs: ((j['docs'] as List?) ?? [])
            .map((d) => CitizenDocument.fromJson(d))
            .toList(),
      );
}

// ── Graph edge ────────────────────────────────────────────────
class GraphEdge {
  final String id;
  final String fromCitizen;
  final String toCitizen;
  final String edgeType;
  final String? evidenceDocId;
  final double confidence;

  const GraphEdge({
    required this.id,
    required this.fromCitizen,
    required this.toCitizen,
    required this.edgeType,
    this.evidenceDocId,
    required this.confidence,
  });

  factory GraphEdge.fromJson(Map<String, dynamic> j) => GraphEdge(
        id: j['id'],
        fromCitizen: j['from_citizen'],
        toCitizen: j['to_citizen'],
        edgeType: j['edge_type'],
        evidenceDocId: j['evidence_doc_id'],
        confidence: (j['confidence'] as num?)?.toDouble() ?? 1.0,
      );

  // Visual properties per edge type
  Color get color {
    switch (edgeType) {
      case 'parent_of':
      case 'child_of':
        return const Color(0xFF1D9E75); // teal
      case 'spouse_of':
        return const Color(0xFF7F77DD); // purple
      case 'owns_property':
        return const Color(0xFFBA7517); // amber
      case 'duplicate_of':
        return const Color(0xFFE24B4A); // red
      case 'sibling_of':
        return const Color(0xFF378ADD); // blue
      default:
        return const Color(0xFF888780); // gray
    }
  }

  bool get isDashed =>
      edgeType == 'duplicate_of' || edgeType == 'owns_property';

  String get label {
    switch (edgeType) {
      case 'parent_of':   return 'parent → child';
      case 'spouse_of':   return 'spouse';
      case 'owns_property': return 'owns property';
      case 'duplicate_of': return 'duplicate flag';
      case 'sibling_of':  return 'sibling';
      default:            return edgeType;
    }
  }
}

// ── Full graph ────────────────────────────────────────────────
class IdentityGraph {
  final List<CitizenNode> nodes;
  final List<GraphEdge> edges;

  const IdentityGraph({required this.nodes, required this.edges});

  factory IdentityGraph.fromJson(Map<String, dynamic> j) => IdentityGraph(
        nodes: ((j['nodes'] as List?) ?? [])
            .map((n) => CitizenNode.fromJson(n))
            .toList(),
        edges: ((j['edges'] as List?) ?? [])
            .map((e) => GraphEdge.fromJson(e))
            .toList(),
      );

  factory IdentityGraph.empty() =>
      const IdentityGraph(nodes: [], edges: []);
}
