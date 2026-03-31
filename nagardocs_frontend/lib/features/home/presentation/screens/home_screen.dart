import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/pulsing_dot.dart';
import '../../../../core/network/dio_client.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/home_provider.dart';
import '../providers/active_jobs_provider.dart';

// ─── Recent Documents Provider ────────────────────────────────────────────────
final recentDocsProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  try {
    final dio = ref.watch(dioProvider);
    final response = await dio.get('/cabinet/documents', queryParameters: {'limit': 5});
    return List<Map<String, dynamic>>.from(response.data ?? []);
  } catch (_) {
    return [];
  }
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with TickerProviderStateMixin {
  late final AnimationController _cardCtrl;
  int _selectedTab = 0;

  final _tabs = const [
    _Tab('Home', Icons.dashboard_rounded),
    _Tab('Scan', Icons.document_scanner_rounded),
    _Tab('Cabinet', Icons.folder_rounded),
    _Tab('Search', Icons.search_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _cardCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _cardCtrl.forward();
  }

  @override
  void dispose() {
    _cardCtrl.dispose();
    super.dispose();
  }

  void _onTabTapped(int index) {
    if (index == _selectedTab) return;
    switch (index) {
      case 0:
        setState(() => _selectedTab = 0);
        break;
      case 1:
        context.push('/upload');
        break;
      case 2:
        context.push('/cabinet');
        break;
      case 3:
        context.push('/search');
        break;
    }
  }

  Widget _buildStatCard(int index, String title, int value, Color color, IconData icon) {
    final anim = CurvedAnimation(
      parent: _cardCtrl,
      curve: Interval(index * 0.1, index * 0.1 + 0.4, curve: Curves.easeOutBack),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(anim),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  if (title == 'Online Now') const PulsingDot(color: AppColors.success),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.bodySm),
                  TweenAnimationBuilder<num>(
                    tween: Tween<num>(begin: 0, end: value),
                    duration: const Duration(milliseconds: 1200),
                    curve: Curves.easeOut,
                    builder: (context, val, _) => Text(
                      val.toInt().toString(),
                      style: AppTextStyles.stat.copyWith(fontSize: 28),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(String title, IconData icon, String route) {
    return GestureDetector(
      onTap: () => context.push(route),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Icon(icon, color: AppColors.primary, size: 28),
          ),
          const SizedBox(height: 8),
          Text(title, style: AppTextStyles.labelMd.copyWith(color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildRecentDocs() {
    final recentAsync = ref.watch(recentDocsProvider);
    return recentAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, _) => const SizedBox.shrink(),
      data: (docs) {
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_rounded, size: 48, color: AppColors.outlineVariant),
                const SizedBox(height: 12),
                Text('No documents yet', style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => context.push('/upload'),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Scan your first document'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                )
              ],
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              tileColor: AppColors.surfaceLowest,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppColors.secondaryContainer, borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.description_rounded, color: AppColors.primary),
              ),
              title: Text(doc['filename'] ?? 'Document', style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(doc['doc_type'] ?? 'Unknown type', style: AppTextStyles.bodySm),
              trailing: TextButton.icon(
                onPressed: () => context.push('/review/${doc['id']}'),
                icon: const Icon(Icons.edit_document, size: 16),
                label: const Text('Review'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              onTap: () => context.push('/review/${doc['id']}'),
            );
          },
        );
      },
    );
  }

  Widget _buildActiveUploads() {
    final activeAsync = ref.watch(activeJobsProvider);
    return activeAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (jobs) {
        if (jobs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const PulsingDot(color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Processing ${jobs.length} Upload${jobs.length == 1 ? '' : 's'}', style: AppTextStyles.headlineSm),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: jobs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final job = jobs[i];
                final filename = job['filename'] ?? 'Document';
                final progress = (job['progress_pct'] as num?)?.toDouble() ?? 0.0;
                final stepInt = (job['step'] as num?)?.toInt() ?? 0;
                
                final stepText = stepInt == 1 ? 'Computing Hash & Duplicates' 
                    : stepInt == 2 ? 'Uploading to Storage'
                    : stepInt == 3 ? 'AI Deep Analysis'
                    : stepInt == 4 ? 'Tamper Detection'
                    : stepInt == 5 ? 'Auto-Sorting into Cabinet'
                    : 'Queued';

                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLowest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(filename, 
                                style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          Text('${(progress * 100).toInt()}%', 
                              style: AppTextStyles.labelMd.copyWith(color: AppColors.primary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: AppColors.surfaceHigh,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('Step $stepInt of 5: $stepText', 
                          style: AppTextStyles.bodySm.copyWith(color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final authState = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: _onTabTapped,
        backgroundColor: AppColors.surfaceLowest,
        indicatorColor: AppColors.secondaryContainer,
        destinations: _tabs.map((t) => NavigationDestination(
          icon: Icon(t.icon),
          label: t.label,
        )).toList(),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeProvider);
          ref.invalidate(recentDocsProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
          SliverAppBar(
            expandedHeight: 130,
            floating: true,
            pinned: true,
            backgroundColor: AppColors.primary,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nagardocs AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                  Text('Officer Dashboard', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 12)),
                ],
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF003A7A), AppColors.primary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          PulsingDot(color: Colors.greenAccent),
                          SizedBox(width: 6),
                          Text('Online', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.white),
                      onSelected: (val) {
                        if (val == 'logout') ref.read(authProvider.notifier).logout();
                      },
                      itemBuilder: (ctx) => [
                        if (authState.isAdmin)
                          const PopupMenuItem(value: 'admin', child: Text('Admin Panel')),
                        const PopupMenuItem(
                          value: 'logout',
                          child: Text('Logout', style: TextStyle(color: AppColors.error)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: state.when(
                loading: () => const Center(child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: AppColors.primary),
                )),
                error: (err, _) => Center(child: Text(err.toString(), style: const TextStyle(color: AppColors.error))),
                data: (metrics) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overview', style: AppTextStyles.headlineSm),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.1,
                      children: [
                        _buildStatCard(0, 'Total Scans', metrics.totalDocs, AppColors.primary, Icons.file_present_rounded),
                        _buildStatCard(1, 'Online Now', metrics.onlineNow, AppColors.success, Icons.groups_rounded),
                        _buildStatCard(2, 'Tamper Alerts', metrics.tamperAlerts, AppColors.error, Icons.warning_amber_rounded),
                        _buildStatCard(3, 'Cabinets', metrics.cabinets, AppColors.tertiary, Icons.folder_special_rounded),
                      ],
                    ),

                    const SizedBox(height: 32),
                    Text('Quick Actions', style: AppTextStyles.headlineSm),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          _buildQuickAction('Scan', Icons.document_scanner_rounded, '/upload'),
                          const SizedBox(width: 24),
                          _buildQuickAction('Cabinet', Icons.folder_rounded, '/cabinet'),
                          const SizedBox(width: 24),
                          _buildQuickAction('Search', Icons.search_rounded, '/search'),
                          const SizedBox(width: 24),
                          _buildQuickAction('Analytics', Icons.bar_chart_rounded, '/analytics'),
                          const SizedBox(width: 24),
                          _buildQuickAction('Graph', Icons.account_tree_outlined, '/graph'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    _buildActiveUploads(),
                    Row(

                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Documents', style: AppTextStyles.headlineSm),
                        TextButton(
                          onPressed: () => context.push('/cabinet'),
                          child: const Text('View All', style: TextStyle(color: AppColors.primary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildRecentDocs(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Tab {
  final String label;
  final IconData icon;
  const _Tab(this.label, this.icon);
}
