// lib/features/graph/data/graph_repository.dart
// Handles all API calls for the Identity Graph feature

import 'package:dio/dio.dart';
import '../domain/graph_models.dart';

class GraphRepository {
  final Dio _dio;

  GraphRepository(this._dio);

  // Fetch full graph for current department
  Future<IdentityGraph> getDepartmentGraph() async {
    final res = await _dio.get('/graph/department');
    return IdentityGraph.fromJson(res.data as Map<String, dynamic>);
  }

  // Fetch single citizen with all docs + edges
  Future<Map<String, dynamic>> getCitizenDetail(String citizenId) async {
    final res = await _dio.get('/graph/citizen/$citizenId');
    return res.data as Map<String, dynamic>;
  }

  // Fetch duplicate flags
  Future<List<dynamic>> getDuplicates() async {
    final res = await _dio.get('/graph/duplicates');
    return res.data as List;
  }

  // Create edge manually
  Future<void> createEdge({
    required String fromCitizen,
    required String toCitizen,
    required String edgeType,
    String? evidenceDocId,
  }) async {
    final data = <String, dynamic>{
      'from_citizen': fromCitizen,
      'to_citizen': toCitizen,
      'edge_type': edgeType,
    };
    if (evidenceDocId != null) {
      data['evidence_doc_id'] = evidenceDocId;
    }
    
    await _dio.post('/graph/edge', data: data);
  }

  // Reprocess a document to re-extract relationships
  Future<void> reprocessDocument(String documentId) async {
    await _dio.post('/graph/reprocess/$documentId');
  }
}
