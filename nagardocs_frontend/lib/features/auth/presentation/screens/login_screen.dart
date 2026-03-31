import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math' as math;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../providers/auth_provider.dart';
import 'pin_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with TickerProviderStateMixin {
  late AnimationController _slideCtrl;
  late AnimationController _flipCtrl;
  late AnimationController _shakeCtrl;

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();

  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _flipCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _shakeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    
    // Slide up on focus
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    _flipCtrl.dispose();
    _shakeCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _handleLogin() async {
    final success = await ref.read(authProvider.notifier).login(
      _emailCtrl.text,
      _passCtrl.text,
      '',
    );
    
    if (!mounted) return;
    
    if (success) {
      setState(() => _isFlipped = true);
      await _flipCtrl.forward();

      if (!mounted) return;

      // ── PIN gate: check if user has PIN set ──────────────────────────────
      final pinNotifier = ref.read(pinProvider.notifier);
      final authState = ref.read(authProvider);
      // Read stored userId from secure storage (written on login)
      final storage = FlutterSecureStorage();
      final userId = await storage.read(key: 'auth_user_id');
      
      debugPrint('---- PIN GATE CHECK ----');
      debugPrint('UserId from storage: $userId');

      if (userId != null) {
        final hasPin = await pinNotifier.checkHasPin(userId);
        debugPrint('Has Pin: $hasPin');
        if (!mounted) return;

        final pinOk = await showPinBottomSheet(
          context: context,
          userId: userId,
          mode: hasPin ? PinScreenMode.verify : PinScreenMode.set,
        );

        if (!mounted) return;
        if (pinOk) {
          context.go(authState.isAdmin ? '/admin' : '/home');
        } else {
          // PIN cancelled / failed — log out
          ref.read(authProvider.notifier).logout();
          setState(() {
            _isFlipped = false;
            _flipCtrl.reset();
          });
        }
      } else {
        // No userId stored — skip PIN and go home
        if (mounted) context.go(authState.isAdmin ? '/admin' : '/home');
      }
    } else {
      _shakeCtrl.forward(from: 0.0);
      final err = ref.read(authProvider).errorMessage ?? 'Login Failed';
      if (mounted) AppSnackbar.showError(context, err);
    }
  }

  Widget _buildLoginForm() {
    final state = ref.watch(authProvider);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceLowest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Welcome Back', style: AppTextStyles.headlineSm),
          const SizedBox(height: 8),
          Text('Login to your dashboard', style: AppTextStyles.bodyMd),
          const SizedBox(height: 32),
          AppTextField(label: 'Email Address', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          AppTextField(label: 'Password', controller: _passCtrl, isPassword: true),
          const SizedBox(height: 32),
          AppButton(
            text: 'Login Securely',
            isLoading: state.status == AuthStatus.loading,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => context.push('/register'),
            child: Text('Register new account', style: AppTextStyles.bodyMd.copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard() {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()..rotateY(math.pi),
      child: Container(
        height: 400,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryContainer]),
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white, size: 80),
              SizedBox(height: 16),
              Text('Secure Login Successful', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Top Navy Header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: MediaQuery.of(context).size.height * 0.4,
            child: Container(
              color: AppColors.primary,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40.0),
                  child: Column(
                    children: [
                      Image.asset('assets/nagardocs_ai_logo.png', height: 80, width: 80, fit: BoxFit.contain),
                      const SizedBox(height: 16),
                      Text('Nagardocs AI', style: AppTextStyles.displayMd.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Form Card
          SafeArea(
            child: Align(
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
                      .animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic)),
                  child: AnimatedBuilder(
                    animation: _shakeCtrl,
                    builder: (context, child) {
                      final sineValue = math.sin(_shakeCtrl.value * math.pi * 3);
                      return Transform.translate(
                        offset: Offset(sineValue * 8, 0),
                        child: child,
                      );
                    },
                    child: AnimatedBuilder(
                      animation: _flipCtrl,
                      builder: (context, child) {
                        return Transform(
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.001)
                            ..rotateY(_flipCtrl.value * math.pi),
                          alignment: Alignment.center,
                          child: _isFlipped ? _buildSuccessCard() : _buildLoginForm(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
