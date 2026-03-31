import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/app_snackbar.dart';
import 'admin_screen.dart'; // To access adminSecurityProvider

class BulkReviewScreen extends ConsumerStatefulWidget {
  const BulkReviewScreen({super.key});

  @override
  ConsumerState<BulkReviewScreen> createState() => _BulkReviewScreenState();
}

class _BulkReviewScreenState extends ConsumerState<BulkReviewScreen> {
  final Set<String> _selectedIds = {};
  bool _isProcessing = false;

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll(List<dynamic> docs) {
    setState(() {
      if (_selectedIds.length == docs.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(docs.map((d) => d['id'].toString()));
      }
    });
  }

  Future<void> _processBulkTarget(String action) async {
    if (_selectedIds.isEmpty) return;

    setState(() => _isProcessing = true);
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post('/admin/bulk-review', data: {
        'document_ids': _selectedIds.toList(),
        'action': action,
      });
      
      if (mounted) {
        AppSnackbar.showSuccess(context, response.data['message'] ?? 'Successfully processed ${_selectedIds.length} documents.');
      }
      
      setState(() => _selectedIds.clear());
      ref.invalidate(adminSecurityProvider); // Refresh the list
    } catch (e) {
      if (mounted) {
        AppSnackbar.showError(context, 'Failed to process documents: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final securityState = ref.watch(adminSecurityProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Bulk Document Review', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: securityState.when(
        data: (data) {
          final List<dynamic> tamperedDocs = data['tampered_documents'] ?? [];

          if (tamperedDocs.isEmpty) {
            return const Center(child: Text("No documents pending review. You're all caught up!", style: TextStyle(color: Colors.grey)));
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${tamperedDocs.length} Flagged Documents',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.textPrimary),
                    ),
                    TextButton.icon(
                      onPressed: () => _selectAll(tamperedDocs),
                      icon: Icon(
                        _selectedIds.length == tamperedDocs.length ? Icons.deselect : Icons.select_all,
                        size: 18,
                      ),
                      label: Text(_selectedIds.length == tamperedDocs.length ? 'Deselect All' : 'Select All'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: tamperedDocs.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = tamperedDocs[index];
                    final docId = doc['id'];
                    final isSelected = _selectedIds.contains(docId);
                    final flags = List<String>.from(doc['tamper_flags'] ?? []);

                    return ListTile(
                      tileColor: isSelected ? AppColors.primary.withValues(alpha: 0.05) : Colors.white,
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) => _toggleSelection(docId),
                      ),
                      title: Text(doc['filename'] ?? 'Unknown File', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Type: ${doc['doc_type'] ?? 'Unknown'}', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                          if (flags.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: flags.map((f) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.red.shade200)),
                                child: Text(f, style: TextStyle(fontSize: 10, color: Colors.red.shade700)),
                              )).toList(),
                            )
                          ]
                        ],
                      ),
                      onTap: () => _toggleSelection(docId),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading documents', style: TextStyle(color: AppColors.error))),
      ),
      bottomNavigationBar: _selectedIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Text('${_selectedIds.length} Selected', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Spacer(),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: AppColors.error, side: const BorderSide(color: AppColors.error)),
                      onPressed: _isProcessing ? null : () => _processBulkTarget('reject'),
                      icon: const Icon(Icons.delete_forever),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
                      onPressed: _isProcessing ? null : () => _processBulkTarget('approve'),
                      icon: _isProcessing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                      label: const Text('Approve'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}
