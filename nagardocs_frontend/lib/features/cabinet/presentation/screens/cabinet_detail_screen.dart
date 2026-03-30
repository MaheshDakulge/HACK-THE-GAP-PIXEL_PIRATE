import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────
final folderDocumentsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, folderId) async {
  final dio = ref.watch(dioProvider);
  final response = await dio.get('/cabinet/$folderId/documents');
  return List<Map<String, dynamic>>.from(response.data ?? []);
});

class CabinetDetailScreen extends ConsumerWidget {
  final String folderId;
  const CabinetDetailScreen({super.key, required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(folderDocumentsProvider(folderId));
    String title = 'Documents';
    if (folderId.startsWith('personal_')) {
      title = folderId.substring(9);
    } else if (folderId == 'unassigned') {
      title = 'My Uploads';
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/cabinet'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () => ref.invalidate(folderDocumentsProvider(folderId)),
          ),
        ],
      ),
      body: Hero(
        tag: 'folder_$folderId',
        child: Material(
          color: Colors.transparent,
          child: docsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 60, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text('Failed to load documents:\n$e',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => ref.invalidate(folderDocumentsProvider(folderId)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
            data: (docs) {
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(folderDocumentsProvider(folderId)),
                child: docs.isEmpty
                    ? CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverFillRemaining(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.folder_open_rounded, size: 72, color: AppColors.outlineVariant),
                                    const SizedBox(height: 16),
                                    Text('This folder is empty', style: AppTextStyles.h2),
                                    const SizedBox(height: 8),
                                    Text('Upload a document to populate this folder.',
                                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
                                        textAlign: TextAlign.center),
                                    const SizedBox(height: 24),
                                    ElevatedButton.icon(
                                      onPressed: () => context.push('/upload'),
                                      icon: const Icon(Icons.upload_file_rounded),
                                      label: const Text('Upload Document'),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        ],
                      )
                    : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final doc = docs[i];
                  final isTampered = doc['is_tampered'] == true;
                  final confidence = (doc['ocr_confidence'] as num?)?.toDouble() ?? 0.9;
                  final uploadedBy = doc['users']?['name'] ?? 'Unknown';
                  final createdAt = doc['created_at'] ?? '';
                  final shortDate = createdAt.length >= 10 ? createdAt.substring(0, 10) : '';
                  final fields = List<Map<String, dynamic>>.from(doc['document_fields'] ?? []);

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLowest,
                      borderRadius: BorderRadius.circular(14),
                      border: isTampered
                          ? Border.all(color: AppColors.error.withValues(alpha: 0.5), width: 1.5)
                          : null,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Dismissible(
                      key: Key(doc['id']),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                      ),
                      confirmDismiss: (direction) async {
                        return await showDialog(
                          context: context,
                          builder: (c) => AlertDialog(
                            title: const Text('Delete Document'),
                            content: const Text('Are you sure you want to delete this document?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: const Text('Delete', style: TextStyle(color: AppColors.error)),
                              ),
                            ],
                          ),
                        );
                      },
                      onDismissed: (direction) async {
                        if (doc['id'] == null) return;
                        try {
                          final dio = ref.read(dioProvider);
                          await dio.delete('/cabinet/documents/${doc['id']}');
                          ref.invalidate(folderDocumentsProvider(folderId));
                          // Note: we can't cleanly import home/cabinet providers here without risking cycles/mess
                          // But popping back to cabinet tab refreshes cabinet if provider is autoDispose
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Failed to delete document')),
                            );
                            ref.invalidate(folderDocumentsProvider(folderId));
                          }
                        }
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        leading: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: isTampered
                                ? AppColors.error.withValues(alpha: 0.1)
                                : AppColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            isTampered ? Icons.warning_amber_rounded : Icons.description_rounded,
                            color: isTampered ? AppColors.error : AppColors.primary,
                          ),
                        ),
                        title: Text(
                          doc['filename'] ?? 'Document',
                          style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                _Tag(doc['doc_type'] ?? 'Unknown', AppColors.primary),
                                const SizedBox(width: 6),
                                _Tag('${(confidence * 100).toInt()}% confidence',
                                    confidence > 0.85 ? AppColors.success : AppColors.warning),
                                if (isTampered) ...[
                                  const SizedBox(width: 6),
                                  _Tag('⚠ Tampered', AppColors.error),
                                ],
                              ]),
                              if (fields.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  fields.take(2).map((f) => '${f['label']}: ${f['value']}').join('  •  '),
                                  style: AppTextStyles.bodySm,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text('By $uploadedBy  •  $shortDate', style: AppTextStyles.bodySm),
                            ],
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                        onTap: () => context.push('/result/${doc['id']}').then((_) => ref.invalidate(folderDocumentsProvider(folderId))),
                      ),
                    ),
                  );
                },
              ),
            );
          },
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
