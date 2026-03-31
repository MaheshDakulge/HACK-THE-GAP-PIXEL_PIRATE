import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/upload_provider.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});

  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      allowedExtensions: ['pdf', 'jpg', 'png', 'jpeg'],
    );

    if (result != null && result.files.isNotEmpty) {
      if (result.files.length == 1 && result.files.single.path != null) {
        // Single file flow -> jump to processing screen for immediate review
        final success = await ref.read(uploadProvider.notifier).uploadDocument(result.files.single.path!);
        if (success) {
          if (mounted) context.push('/processing');
        }
      } else {
        // Multiple files flow -> batch upload in background
        final paths = result.files.map((f) => f.path).whereType<String>().toList();
        if (paths.isNotEmpty) {
          ref.read(uploadProvider.notifier).uploadMultipleDocuments(paths);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Uploading & Processing ${paths.length} documents in the background...'),
                backgroundColor: AppColors.primary,
                duration: const Duration(seconds: 4),
              ),
            );
            // Go to home where user can eventually check the cabinet
            context.go('/home');
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan & Upload', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.background,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const Text(
              'How would you like to add the document?',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            
            // 1. SCANNER BUTTON
            _buildActionCard(
              title: 'Scan Document',
              subtitle: 'Use AI camera to auto-crop & enhance',
              icon: Icons.document_scanner_rounded,
              color: AppColors.primary,
              onTap: () => context.push('/scan'),
            ),
            
            const SizedBox(height: 24),
            
            // 2. FILE PICKER BUTTON
            _buildActionCard(
              title: 'Upload File',
              subtitle: 'Select PDF, JPG, or PNG from storage',
              icon: Icons.upload_file_rounded,
              color: AppColors.textSecondary,
              onTap: _pickFile,
            ),
            
            const SizedBox(height: 48),
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surfaceLowest,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Auto-Detected Types', style: AppTextStyles.bodyLg.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildChip('Marksheet'),
                      _buildChip('Birth Cert.'),
                      _buildChip('Property'),
                      _buildChip('Income'),
                      _buildChip('Ration'),
                    ],
                  )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surfaceLowest,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.h2.copyWith(color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.outlineVariant, width: 1),
      ),
      child: Text(label, style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
    );
  }
}
