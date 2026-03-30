import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';

// Maps category names returned by backend to Material icon + gradient colors
const _kCategoryMeta = <String, Map<String, dynamic>>{
  'Identity Documents':        {'icon': Icons.badge_rounded,          'colors': [Color(0xFF1A73E8), Color(0xFF0D47A1)]},
  'Property Tax':              {'icon': Icons.home_work_rounded,       'colors': [Color(0xFF6A1B9A), Color(0xFF4A148C)]},
  'Water Bills':               {'icon': Icons.water_drop_rounded,      'colors': [Color(0xFF0288D1), Color(0xFF01579B)]},
  'Land Records':              {'icon': Icons.landscape_rounded,       'colors': [Color(0xFF2E7D32), Color(0xFF1B5E20)]},
  'Certificates':              {'icon': Icons.verified_rounded,        'colors': [Color(0xFFAD1457), Color(0xFF880E4F)]},
  'Other':                     {'icon': Icons.folder_open_rounded,     'colors': [Color(0xFF757575), Color(0xFF424242)]},
  'My Uploads':                {'icon': Icons.folder_shared_rounded,   'colors': [Color(0xFF1A73E8), Color(0xFF0D47A1)]},
  'Needs Review':              {'icon': Icons.rate_review_rounded,     'colors': [Color(0xFFFF8F00), Color(0xFFE65100)]},
};

Map<String, dynamic> categoryMeta(String name) =>
    _kCategoryMeta[name] ??
    {'icon': Icons.folder_rounded, 'colors': const [Color(0xFF1A73E8), Color(0xFF0D47A1)]};

class CabinetFolder {
  final String id;
  final String name;
  final int documentCount;
  final IconData icon;
  final List<Color> gradientColors;

  CabinetFolder({
    required this.id,
    required this.name,
    required this.documentCount,
    required this.icon,
    required this.gradientColors,
  });

  factory CabinetFolder.fromJson(Map<String, dynamic> json) {
    int docCount = 0;
    if (json['document_count'] is int) {
      docCount = json['document_count'] as int;
    } else if (json['documents'] is List) {
      final docs = json['documents'] as List;
      if (docs.isNotEmpty) docCount = (docs[0]['count'] as num?)?.toInt() ?? 0;
    }

    final meta = categoryMeta(json['name'] ?? '');
    return CabinetFolder(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown',
      documentCount: docCount,
      icon: meta['icon'] as IconData,
      gradientColors: List<Color>.from(meta['colors'] as List),
    );
  }
}

final cabinetListProvider = NotifierProvider<CabinetListNotifier, AsyncValue<List<CabinetFolder>>>(CabinetListNotifier.new);

class CabinetListNotifier extends Notifier<AsyncValue<List<CabinetFolder>>> {
  @override
  AsyncValue<List<CabinetFolder>> build() {
    fetchFolders();
    return const AsyncValue.loading();
  }

  Future<void> fetchFolders() async {
    state = const AsyncValue.loading();
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/cabinet/folders');
      final list = (response.data as List).map((e) => CabinetFolder.fromJson(e)).toList();
      state = AsyncValue.data(list);
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }
}

