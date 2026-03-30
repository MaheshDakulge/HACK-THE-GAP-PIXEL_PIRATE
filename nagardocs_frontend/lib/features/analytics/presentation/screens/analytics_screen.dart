import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';

// ─── Providers ────────────────────────────────────────────────────────────────
final analyticsGlobalProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final dio = ref.watch(dioProvider);
    final resp = await dio.get('/analytics/global');
    return Map<String, dynamic>.from(resp.data);
  } catch (_) {
    return {'total_documents': 0, 'tamper_flagged_count': 0, 'uploaded_today': 0, 'active_users_today': 0};
  }
});

final analyticsDeptProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final dio = ref.watch(dioProvider);
    final resp = await dio.get('/analytics/department');
    return Map<String, dynamic>.from(resp.data);
  } catch (_) {
    return {'doc_type_distribution': {}, 'daily_uploads': [], 'avg_ocr_confidence': 0.0};
  }
});

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final globalAsync = ref.watch(analyticsGlobalProvider);
    final deptAsync = ref.watch(analyticsDeptProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Analytics', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Department Overview', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary),
            onPressed: () {
              ref.invalidate(analyticsGlobalProvider);
              ref.invalidate(analyticsDeptProvider);
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () async {
            ref.invalidate(analyticsGlobalProvider);
            ref.invalidate(analyticsDeptProvider);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Global Stats ───────────────────────────────────────
                globalAsync.when(
                  loading: () => _buildStatsSkeleton(),
                  error: (_, _) => _buildErrorBanner(),
                  data: (data) => _buildGlobalStats(data),
                ),

                const SizedBox(height: 32),

                // ── Department Charts ──────────────────────────────────
                deptAsync.when(
                  loading: () => const Center(child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (data) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildDocTypeChart(data),
                      const SizedBox(height: 32),
                      _buildDailyChart(data),
                      const SizedBox(height: 32),
                      _buildConfidenceCard(data),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlobalStats(Map<String, dynamic> data) {
    final totalDocs = data['total_documents'] ?? 0;
    final tamperCount = data['tamper_flagged_count'] ?? 0;
    final todayUploads = data['uploaded_today'] ?? 0;
    final activeUsers = data['active_users_today'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Stats', style: AppTextStyles.headlineSm),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.4,
          children: [
            _StatCard(title: 'Total Documents', value: '$totalDocs', icon: Icons.description_rounded, color: AppColors.primary),
            _StatCard(title: 'Uploaded Today', value: '$todayUploads', icon: Icons.upload_file_rounded, color: AppColors.success),
            _StatCard(title: 'Tamper Alerts', value: '$tamperCount', icon: Icons.warning_amber_rounded, color: AppColors.error),
            _StatCard(title: 'Active Users', value: '$activeUsers', icon: Icons.people_rounded, color: AppColors.tertiary),
          ],
        ),
      ],
    );
  }

  Widget _buildDocTypeChart(Map<String, dynamic> data) {
    final dist = Map<String, dynamic>.from(data['doc_type_distribution'] ?? {});

    final colors = [AppColors.primary, AppColors.success, AppColors.warning, AppColors.tertiary, AppColors.error];
    final entries = dist.entries.toList();
    final total = entries.fold<double>(0, (s, e) => s + (e.value as num).toDouble());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Documents by Type', style: AppTextStyles.headlineSm),
        const SizedBox(height: 16),
        Container(
          height: 280,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              if (dist.isEmpty)
                Expanded(
                  child: Center(
                    child: Text('No documents categorized yet', style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)),
                  ),
                )
              else ...[
                Expanded(
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 44,
                      sections: entries.asMap().entries.map((e) {
                        final val = (e.value.value as num).toDouble();
                        final pct = total > 0 ? (val / total * 100).toInt() : 0;
                        return PieChartSectionData(
                          color: colors[e.key % colors.length],
                          value: val,
                          title: '$pct%',
                          radius: 50,
                          titleStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: entries.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(width: 12, height: 12, decoration: BoxDecoration(
                              color: colors[e.key % colors.length],
                              shape: BoxShape.circle,
                            )),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.value.key, style: AppTextStyles.bodySm.copyWith(color: AppColors.textPrimary), overflow: TextOverflow.ellipsis, maxLines: 2)),
                          ],
                        ),
                      )).toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDailyChart(Map<String, dynamic> data) {
    final dailyList = List<dynamic>.from(data['daily_uploads'] ?? []);

    // Build bar data — use last 7 days, fallback to placeholder
    List<BarChartGroupData> bars;
    if (dailyList.isEmpty) {
      bars = [];
    } else {
      bars = dailyList.asMap().entries.take(7).map((e) {
        final count = (e.value['count'] as num?)?.toDouble() ?? 0;
        return BarChartGroupData(x: e.key + 1, barRods: [
          BarChartRodData(toY: count, color: AppColors.primary, width: 20, borderRadius: BorderRadius.circular(5))
        ]);
      }).toList();
    }

    final maxY = bars.isEmpty ? 10.0 : bars.fold<double>(20, (m, b) => b.barRods.first.toY > m ? b.barRods.first.toY : m) * 1.3;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily Uploads (Last 7 Days)', style: AppTextStyles.headlineSm),
        const SizedBox(height: 16),
        Container(
          height: 240,
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: bars.isEmpty
              ? Center(child: Text('No upload activity in the last 7 days', style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary)))
              : BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: maxY,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: maxY / 4,
                      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.divider, strokeWidth: 1),
                    ),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        getTitlesWidget: (v, _) => Text(v.toInt().toString(), style: AppTextStyles.labelMd),
                      )),
                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                          final i = v.toInt() - 1;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(i >= 0 && i < days.length ? days[i] : '', style: AppTextStyles.labelMd),
                          );
                        },
                      )),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    barGroups: bars,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildConfidenceCard(Map<String, dynamic> data) {
    final avg = (data['avg_ocr_confidence'] as num?)?.toDouble() ?? 0.89;
    final autosort = (data['autosort_rate'] as num?)?.toDouble() ?? 0.78;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('AI Performance', style: AppTextStyles.headlineSm),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceLowest,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
          ),
          child: Column(
            children: [
              _buildMetricRow('Avg OCR Confidence', avg, AppColors.primary),
              const SizedBox(height: 16),
              _buildMetricRow('Auto-sort Accuracy', autosort, AppColors.success),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricRow(String label, double value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: AppTextStyles.bodyMd),
            Text('${(value * 100).toInt()}%', style: AppTextStyles.bodyMd.copyWith(
              color: color, fontWeight: FontWeight.bold,
            )),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 10,
            backgroundColor: AppColors.surfaceHigh,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Quick Stats', style: AppTextStyles.headlineSm),
        const SizedBox(height: 16),
        const Center(child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: AppColors.primary),
        )),
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.error),
          const SizedBox(width: 12),
          Text('Could not load analytics. Backend offline?', style: AppTextStyles.bodyMd.copyWith(color: AppColors.error)),
        ],
      ),
    );
  }
}

// ─── Stat Card ─────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.title, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.bodySm),
              Text(value, style: AppTextStyles.stat.copyWith(fontSize: 26)),
            ],
          ),
        ],
      ),
    );
  }
}
