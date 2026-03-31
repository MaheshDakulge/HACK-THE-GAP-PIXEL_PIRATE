import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();

  late AnimationController _animController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _nameCtrl.dispose();
    _deptCtrl.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _handleRegister() async {
    final success = await ref.read(authProvider.notifier).register(
      _nameCtrl.text,
      _emailCtrl.text,
      _passwordCtrl.text,
      _deptCtrl.text,
    );
    
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created! Waiting for Admin approval.', style: TextStyle(color: Colors.white)), backgroundColor: AppColors.success),
      );
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceHighest,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(color: AppColors.primary.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset('assets/nagardocs_ai_logo.png', height: 64, width: 64, fit: BoxFit.contain),
                      const SizedBox(height: 24),
                      Text('Create Account', style: AppTextStyles.displayMd.copyWith(color: AppColors.textPrimary), textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('Join Nagardocs AI to accelerate document processing.', style: AppTextStyles.bodyLg.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                      
                      AppTextField(
                        controller: _nameCtrl,
                        label: 'Full Name',
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _emailCtrl,
                        label: 'Email Address',
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _passwordCtrl,
                        label: 'Password',
                        isPassword: true,
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _deptCtrl,
                        label: 'Department Code (Optional)',
                      ),
                      
                      if (authState.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(authState.errorMessage!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                      ],
                      
                      const SizedBox(height: 32),
                      AppButton(
                        text: 'Register Account',
                        isLoading: isLoading,
                        onPressed: _handleRegister,
                      ),
                      const SizedBox(height: 24),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text('Already have an account? Sign In', style: AppTextStyles.bodyLg.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
