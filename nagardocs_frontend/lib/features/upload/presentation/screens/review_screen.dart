import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../providers/review_cache_provider.dart';

// ─── Provider ─────────────────────────────────────────────────────────────────
final _reviewDocProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, docId) async {
  // Fix 2: Use pre-fetched cache from ProcessingScreen if available.
  // This avoids a redundant network round-trip on every navigation.
  final cached = ref.read(reviewDocCacheProvider);
  if (cached != null) {
    // Riverpod forbids modifying state during provider initialization.
    // We will let the cache be overwritten by the next upload.
    return cached;
  }
  // Fallback: fetch from network (e.g. if navigating directly to review URL)
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/cabinet/documents/$docId');
  return Map<String, dynamic>.from(res.data);
});

// ─── Review Screen ─────────────────────────────────────────────────────────────
class ReviewScreen extends ConsumerStatefulWidget {
  final String docId;
  final bool isDuplicate;
  const ReviewScreen({super.key, required this.docId, this.isDuplicate = false});

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  final _formKey = GlobalKey<FormState>();
  final List<_FieldEntry> _fields = [];
  bool _isSaving = false;
  bool _isInitialized = false;

  void _initFields(Map<String, dynamic> doc) {
    if (_isInitialized) return;
    _isInitialized = true;
    final raw = List<Map<String, dynamic>>.from(doc['document_fields'] ?? []);
    for (final f in raw) {
      final labelStr = f['label'] as String? ?? '';
      if (labelStr.startsWith('system_')) continue;
      
      _fields.add(_FieldEntry(
        id: f['id'] as String?,
        label: labelStr,
        controller: TextEditingController(text: f['value'] as String? ?? ''),
      ));
    }
    // If no fields were extracted, add a blank row for manual entry
    if (_fields.isEmpty) {
      _fields.add(_FieldEntry(
        label: 'Notes',
        controller: TextEditingController(),
      ));
    }
    setState(() {});
  }

  void _addField() {
    setState(() {
      _fields.add(_FieldEntry(
        label: '',
        controller: TextEditingController(),
      ));
    });
  }

  void _removeField(int index) {
    setState(() {
      _fields[index].controller.dispose();
      _fields.removeAt(index);
    });
  }

  Future<void> _confirmAndSave(Map<String, dynamic> doc) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final dio = ref.read(dioProvider);
      final payload = _fields
          .where((f) => f.labelController.text.trim().isNotEmpty)
          .map((f) => {
                'id': f.id,
                'label': f.labelController.text.trim(),
                'value': f.controller.text.trim(),
              })
          .toList();

      await dio.put('/cabinet/documents/${widget.docId}/fields', data: payload);
      if (!mounted) return;
      AppSnackbar.showSuccess(context, '✅ Document saved to Cabinet!');
      context.go('/cabinet');
    } catch (e) {
      if (!mounted) return;
      AppSnackbar.showError(context, 'Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.controller.dispose();
      f.labelController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_reviewDocProvider(widget.docId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Review Extracted Data',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/cabinet'),
        ),
        actions: [
          if (widget.isDuplicate)
            TextButton.icon(
              onPressed: () => context.go('/upload'),
              icon: const Icon(Icons.document_scanner_rounded, size: 18),
              label: Text('Rescan',
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
            ),
          TextButton(
            onPressed: () => context.go('/cabinet'),
            child: Text('Discard',
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 64, color: AppColors.error),
              const SizedBox(height: 16),
              Text('Failed to load document\n$e',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(_reviewDocProvider(widget.docId)),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (doc) {
          _initFields(doc);
          final docType = doc['doc_type'] as String? ?? 'Document';
          final confidence =
              (doc['ocr_confidence'] as num?)?.toDouble() ?? 0.0;
          final isTampered = doc['is_tampered'] == true;
          final tamperFlags =
              List<String>.from(doc['tamper_flags'] ?? []);

          return Form(
            key: _formKey,
            child: Column(
              children: [
                // Status banner
                _StatusBanner(
                    isTampered: isTampered, tamperFlags: tamperFlags),
                    
                if (widget.isDuplicate)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: AppColors.warning.withValues(alpha: 0.15),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Exact duplicate detected. This is your existing active document.',
                            style: AppTextStyles.bodySm.copyWith(color: AppColors.warning, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),

                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      // Document info card
                      _InfoCard(docType: docType, confidence: confidence,
                          filename: doc['filename'] as String? ?? ''),
                      const SizedBox(height: 24),

                      // Fields header
                      Row(
                        children: [
                          Expanded(
                            child: Text('Extracted Fields',
                                style: AppTextStyles.headlineSm),
                          ),
                          TextButton.icon(
                            onPressed: _addField,
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add Field'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Verify and correct any field below before saving.',
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),

                      // Editable fields
                      ..._fields.asMap().entries.map((entry) {
                        final i = entry.key;
                        final field = entry.value;
                        return _EditableFieldRow(
                          field: field,
                          onDelete: () => _removeField(i),
                        );
                      }),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),

                // Confirm button fixed at bottom
                _ConfirmBar(
                  isSaving: _isSaving,
                  onConfirm: () => _confirmAndSave(doc),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Sub widgets ──────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  final bool isTampered;
  final List<String> tamperFlags;
  const _StatusBanner({required this.isTampered, required this.tamperFlags});

  @override
  Widget build(BuildContext context) {
    final color = isTampered ? AppColors.error : AppColors.success;
    final icon = isTampered
        ? Icons.warning_amber_rounded
        : Icons.verified_rounded;
    final title = isTampered ? '⚠️ Anomalies Detected' : '✅ Document Verified';
    final subtitle = isTampered
        ? tamperFlags.join(' • ')
        : 'AI analysis passed all checks.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.3))),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyMd.copyWith(
                        color: color, fontWeight: FontWeight.w700)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: AppTextStyles.bodySm
                          .copyWith(color: color.withValues(alpha: 0.8)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String docType;
  final double confidence;
  final String filename;
  const _InfoCard(
      {required this.docType,
      required this.confidence,
      required this.filename});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).toInt();
    final confColor = pct >= 80
        ? AppColors.success
        : pct >= 50
            ? AppColors.warning
            : AppColors.error;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.description_rounded,
                color: AppColors.primary, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(filename,
                    style:
                        AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _Chip(label: docType, color: AppColors.primary),
                    const SizedBox(width: 8),
                    _Chip(label: '$pct% Confidence', color: confColor),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: AppTextStyles.labelMd.copyWith(
              color: color, fontWeight: FontWeight.w600)),
    );
  }
}

class _EditableFieldRow extends StatelessWidget {
  final _FieldEntry field;
  final VoidCallback onDelete;
  const _EditableFieldRow({required this.field, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: field.labelController,
              style: AppTextStyles.bodySm
                  .copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                hintText: 'Label',
                hintStyle: AppTextStyles.bodySm
                    .copyWith(color: AppColors.textSecondary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: field.controller,
              style: AppTextStyles.bodyMd,
              decoration: InputDecoration(
                hintText: 'Value',
                hintStyle: AppTextStyles.bodyMd
                    .copyWith(color: AppColors.textSecondary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 1.5),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onConfirm;
  const _ConfirmBar({required this.isSaving, required this.onConfirm});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
            top: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.3))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: isSaving ? null : onConfirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 20),
            label: Text(
              isSaving ? 'Saving...' : 'Confirm & Save to Cabinet',
              style: AppTextStyles.bodyMd.copyWith(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Field Entry Model ────────────────────────────────────────────────────────
class _FieldEntry {
  final String? id;
  final String label;
  late final TextEditingController labelController;
  final TextEditingController controller;

  _FieldEntry({
    this.id,
    required this.label,
    required this.controller,
  }) {
    labelController = TextEditingController(text: label);
  }
}
