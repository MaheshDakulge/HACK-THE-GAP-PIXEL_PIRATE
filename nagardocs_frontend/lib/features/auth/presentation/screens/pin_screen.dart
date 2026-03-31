import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/network/dio_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final pinProvider = NotifierProvider<PinNotifier, PinState>(PinNotifier.new);

enum PinScreenMode { set, verify }

class PinState {
  final PinScreenMode mode;
  final bool isLoading;
  final String? error;
  final bool isLocked;
  final String? lockMessage;
  final bool success;

  const PinState({
    this.mode = PinScreenMode.verify,
    this.isLoading = false,
    this.error,
    this.isLocked = false,
    this.lockMessage,
    this.success = false,
  });

  PinState copyWith({
    PinScreenMode? mode,
    bool? isLoading,
    String? error,
    bool? isLocked,
    String? lockMessage,
    bool? success,
  }) =>
      PinState(
        mode: mode ?? this.mode,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isLocked: isLocked ?? this.isLocked,
        lockMessage: lockMessage,
        success: success ?? this.success,
      );
}

class PinNotifier extends Notifier<PinState> {
  @override
  PinState build() => const PinState();

  Future<bool> checkHasPin(String userId) async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/auth/pin/status/$userId');
      return res.data['has_pin'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setPin(String userId, String pin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/pin/set', data: {'user_id': userId, 'pin': pin});
      state = state.copyWith(isLoading: false, success: true);
      return true;
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail'] ?? 'Failed to set PIN';
      state = state.copyWith(isLoading: false, error: msg);
      return false;
    }
  }

  Future<bool> verifyPin(String userId, String pin) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final dio = ref.read(dioProvider);
      await dio.post('/auth/pin/verify', data: {'user_id': userId, 'pin': pin});
      state = state.copyWith(isLoading: false, success: true);
      return true;
    } on DioException catch (e) {
      final data = e.response?.data as Map?;
      final msg = data?['detail'] ?? 'Wrong PIN';
      final isLocked = e.response?.statusCode == 423;
      state = state.copyWith(
        isLoading: false,
        error: msg,
        isLocked: isLocked,
        lockMessage: isLocked ? msg : null,
      );
      return false;
    }
  }

  void reset() {
    state = const PinState();
  }
}

// ── Main Widget (call via showPinBottomSheet) ─────────────────────────────────

Future<bool> showPinBottomSheet({
  required BuildContext context,
  required String userId,
  required PinScreenMode mode,
  String? userName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    enableDrag: false,
    builder: (_) => ProviderScope(
      child: _PinBottomSheet(
        userId: userId,
        mode: mode,
        userName: userName,
      ),
    ),
  );
  return result == true;
}

class _PinBottomSheet extends ConsumerStatefulWidget {
  final String userId;
  final PinScreenMode mode;
  final String? userName;

  const _PinBottomSheet({
    required this.userId,
    required this.mode,
    this.userName,
  });

  @override
  ConsumerState<_PinBottomSheet> createState() => _PinBottomSheetState();
}

class _PinBottomSheetState extends ConsumerState<_PinBottomSheet>
    with TickerProviderStateMixin {
  String _pin = '';
  String? _confirmPin; // only used when mode == set (2-step confirm)
  bool _isConfirmStep = false;

  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;
  late AnimationController _slideCtrl;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();

    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnim = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: -8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _slideAnim = CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic);
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  // ── PIN digit entry ─────────────────────────────────────────────────────────

  void _onDigit(String digit) {
    if (_pin.length >= 4) return;
    HapticFeedback.lightImpact();
    setState(() => _pin += digit);
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 120), _submit);
    }
  }

  void _onDelete() {
    if (_pin.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    final notifier = ref.read(pinProvider.notifier);

    if (widget.mode == PinScreenMode.set) {
      if (!_isConfirmStep) {
        // Step 1: save first entry, ask for confirmation
        setState(() {
          _confirmPin = _pin;
          _pin = '';
          _isConfirmStep = true;
        });
        return;
      }
      // Step 2: confirm match
      if (_pin != _confirmPin) {
        _shake();
        setState(() {
          _pin = '';
          _isConfirmStep = false;
          _confirmPin = null;
        });
        return;
      }
      final success = await notifier.setPin(widget.userId, _pin);
      if (success && mounted) {
        Navigator.of(context).pop(true);
      } else {
        _shake();
      }
    } else {
      final success = await notifier.verifyPin(widget.userId, _pin);
      if (success && mounted) {
        Navigator.of(context).pop(true);
      } else {
        _shake();
        setState(() => _pin = '');
      }
    }
  }

  void _shake() {
    HapticFeedback.vibrate();
    _shakeCtrl.forward(from: 0);
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(pinProvider);

    String title;
    if (widget.mode == PinScreenMode.set) {
      title = _isConfirmStep ? 'Confirm your PIN' : 'Create a 4-digit PIN';
    } else {
      title = 'Enter your PIN';
    }

    return AnimatedBuilder(
      animation: _slideAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, (1 - _slideAnim.value) * 400),
          child: child,
        );
      },
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ────────────────────────────────────────────────
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 28),

            // ── Logo + greeting ───────────────────────────────────────────
            Image.asset('assets/nagardocs_ai_logo.png', height: 52, width: 52),
            const SizedBox(height: 10),
            if (widget.userName != null)
              Text(
                'Welcome, ${widget.userName}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            const SizedBox(height: 4),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 24),

            // ── 4-dot indicator ───────────────────────────────────────────
            AnimatedBuilder(
              animation: _shakeAnim,
              builder: (context, child) => Transform.translate(
                offset: Offset(_shakeAnim.value, 0),
                child: child,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _pin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: filled ? 16 : 14,
                    height: filled ? 16 : 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.primary : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        width: 2,
                      ),
                      boxShadow: filled
                          ? [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.35),
                                blurRadius: 8,
                                spreadRadius: 1,
                              )
                            ]
                          : [],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 10),

            // ── Error / lock message ──────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: (state.error != null || state.isLocked)
                  ? Padding(
                      key: ValueKey(state.error),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        state.isLocked
                            ? '🔒 ${state.lockMessage}'
                            : state.error!,
                        style: TextStyle(
                          color: state.isLocked
                              ? AppColors.warning
                              : AppColors.error,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : const SizedBox(height: 20, key: ValueKey('empty')),
            ),
            const SizedBox(height: 8),

            // ── Numpad ────────────────────────────────────────────────────
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildRow(['1', '2', '3']),
                    const SizedBox(height: 4),
                    _buildRow(['4', '5', '6']),
                    const SizedBox(height: 4),
                    _buildRow(['7', '8', '9']),
                    const SizedBox(height: 4),
                    _buildRow(['', '0', '⌫']),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((k) => _buildKey(k)).toList(),
    );
  }

  Widget _buildKey(String key) {
    final isEmpty = key.isEmpty;
    final isDelete = key == '⌫';

    return GestureDetector(
      onTap: () {
        if (isEmpty) return;
        if (isDelete) {
          _onDelete();
        } else {
          _onDigit(key);
        }
      },
      child: Container(
        width: 80,
        height: 68,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isEmpty
              ? Colors.transparent
              : isDelete
                  ? Colors.transparent
                  : AppColors.surfaceLow,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.center,
        child: isDelete
            ? const Icon(
                Icons.backspace_outlined,
                size: 22,
                color: AppColors.textSecondary,
              )
            : isEmpty
                ? null
                : Text(
                    key,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
      ),
    );
  }
}
