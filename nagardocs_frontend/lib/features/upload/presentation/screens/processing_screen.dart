import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/network/dio_client.dart';
import '../providers/upload_provider.dart';
import '../providers/review_cache_provider.dart';

import '../../../home/presentation/providers/home_provider.dart';
import '../../../cabinet/presentation/providers/cabinet_provider.dart';

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  late AnimationController _pulseController;
  int _pollCount = 0;

  final List<String> _steps = [
    'OCR Text Extraction',
    'AI Classification',
    'Field Extraction',
    'Duplicate Check',
    'Tamper Detection',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scheduleNextPoll();
  }

  // Fix 3: Adaptive polling — fast at first, normal after 3 polls
  void _scheduleNextPoll() {
    final delay = _pollCount < 3
        ? const Duration(milliseconds: 800)
        : const Duration(seconds: 2);

    _timer = Timer(delay, () async {
      _pollCount++;
      await ref.read(uploadProvider.notifier).pollStatus();
      if (mounted) _scheduleNextPoll();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(uploadProvider);

    // Navigate when done
    ref.listen<UploadState>(uploadProvider, (prev, next) async {
      if (next.status == UploadStatus.done && next.documentId != null) {
        _timer?.cancel();
        ref.invalidate(homeProvider);
        ref.invalidate(cabinetListProvider);

        // Fix 2: Pre-fetch doc and store in cache so ReviewScreen
        // can read it instantly without making a second API call.
        try {
          final dio = ref.read(dioProvider);
          final res = await dio.get('/cabinet/documents/${next.documentId}');
          ref.read(reviewDocCacheProvider.notifier).setDoc(
              Map<String, dynamic>.from(res.data as Map));
        } catch (_) {
          // Cache miss is fine — ReviewScreen will fall back to network.
        }

        if (!context.mounted) return;
        final msg = (next.errorMessage ?? '').toLowerCase();
        final isDup = msg.contains('duplicate');
        if (isDup) {
          context.pushReplacement('/review/${next.documentId}?dup=true');
        } else {
          context.pushReplacement('/review/${next.documentId}');
        }
      }
      if (next.status == UploadStatus.error) {
        _timer?.cancel();
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Processing failed'),
            backgroundColor: AppColors.error,
          ),
        );
        context.go('/upload');
      }
    });

    final progress = state.progress;
    final currentStep = state.currentStep;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Text('Analyzing Document', style: AppTextStyles.displayMd),
              const SizedBox(height: 8),
              Text(
                'Nagardocs AI is processing your scan. This takes a few seconds.',
                style: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),

              // Overall progress bar
              Row(
                children: [
                  Expanded(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: progress),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (context, value, _) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            backgroundColor: AppColors.outlineVariant.withValues(alpha: 0.3),
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: AppTextStyles.bodyMd.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Step list
              Expanded(
                child: ListView.builder(
                  itemCount: _steps.length,
                  itemBuilder: (ctx, i) {
                    final stepNumber = i + 1;
                    final isDone = currentStep > stepNumber ||
                        state.status == UploadStatus.done;
                    final isActive = currentStep == stepNumber;

                    return _StepTile(
                      label: _steps[i],
                      isDone: isDone,
                      isActive: isActive,
                      pulseController: _pulseController,
                    );
                  },
                ),
              ),

              // Cancel button
              Center(
                child: TextButton(
                  onPressed: () {
                    ref.read(uploadProvider.notifier).reset();
                    context.go('/upload');
                  },
                  child: Text(
                    'Cancel',
                    style: AppTextStyles.bodyMd.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String label;
  final bool isDone;
  final bool isActive;
  final AnimationController pulseController;

  const _StepTile({
    required this.label,
    required this.isDone,
    required this.isActive,
    required this.pulseController,
  });

  @override
  Widget build(BuildContext context) {
    final Widget icon;

    if (isDone) {
      icon = const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 26);
    } else if (isActive) {
      icon = AnimatedBuilder(
        animation: pulseController,
        builder: (_, _) => Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primary.withValues(
              alpha: 0.2 + 0.5 * pulseController.value,
            ),
          ),
          child: Center(
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      );
    } else {
      icon = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.outlineVariant, width: 1.5),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary.withValues(alpha: 0.06)
            : isDone
                ? AppColors.success.withValues(alpha: 0.04)
                : AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive
              ? AppColors.primary.withValues(alpha: 0.3)
              : isDone
                  ? AppColors.success.withValues(alpha: 0.3)
                  : AppColors.outlineVariant.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodyMd.copyWith(
                color: isDone
                    ? AppColors.success
                    : isActive
                        ? AppColors.primary
                        : AppColors.textSecondary,
                fontWeight: isActive || isDone ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (isActive)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}
