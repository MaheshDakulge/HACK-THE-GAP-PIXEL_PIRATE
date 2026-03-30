import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/cabinet_provider.dart';

class CabinetListScreen extends ConsumerWidget {
  const CabinetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(cabinetListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Digital Cabinet', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Invalidate the provider to re-fetch folders
          ref.invalidate(cabinetListProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16.0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Organized by NagarDocs AI', style: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(
              child: state.when(
                loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                error: (err, _) => Center(child: Text('Failed to load cabinet: $err')),
                data: (folders) {
                  if (folders.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('📄', style: TextStyle(fontSize: 64)),
                          const SizedBox(height: 16),
                          Text('No documents yet', style: AppTextStyles.h2),
                          const SizedBox(height: 8),
                          Text('Upload your first file to get started', style: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary)),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                            onPressed: () => context.go('/upload'), 
                            child: const Text('Go to Upload')
                          )
                        ],
                      ),
                    );
                  }
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      return _CabinetFolderItem(folder: folder);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CabinetFolderItem extends StatelessWidget {
  final CabinetFolder folder;

  const _CabinetFolderItem({required this.folder});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/cabinet/${folder.id}'),
      child: Hero(
        tag: 'folder_${folder.id}',
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: folder.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(24),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: folder.gradientColors[0].withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Stack(
              children: [
                // Inner paper sticking out
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    width: 40,
                    height: 24,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                Positioned.fill(
                  top: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: folder.gradientColors[0].withValues(alpha: 0.9),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Icon(folder.icon, color: Colors.white.withValues(alpha: 0.9), size: 32),
                        const SizedBox(height: 12),
                        Text(folder.name, style: AppTextStyles.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('${folder.documentCount} items', style: AppTextStyles.bodySm.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
