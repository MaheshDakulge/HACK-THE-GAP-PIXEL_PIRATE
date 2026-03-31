import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/upload/presentation/screens/upload_screen.dart';
import '../../features/upload/presentation/screens/processing_screen.dart';
import '../../features/upload/presentation/screens/result_screen.dart';
import '../../features/upload/presentation/screens/review_screen.dart';
import '../../features/cabinet/presentation/screens/cabinet_list_screen.dart';
import '../../features/cabinet/presentation/screens/cabinet_detail_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/analytics/presentation/screens/analytics_screen.dart';
import '../../features/admin/presentation/screens/admin_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/scanner/screens/scanner_screen.dart';
import '../../features/scanner/screens/preview_screen.dart';
import '../../features/graph/presentation/screens/graph_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authState = ref.read(authProvider);
      final isLoggedIn = authState.status == AuthStatus.authenticated;
      final isAdmin = authState.isAdmin;
      final loc = state.uri.toString();
      final goingToAuth = loc == '/login' || loc == '/register';

      if (!isLoggedIn && !goingToAuth) return '/login';

      // Already logged in and trying to access auth pages
      if (isLoggedIn && goingToAuth) {
        return isAdmin ? '/admin' : '/home';
      }

      // Admins get redirected away from officer pages
      if (isLoggedIn && isAdmin && loc == '/home') return '/admin';

      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/login'),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      GoRoute(path: '/home', builder: (context, state) => const HomeScreen()),
      GoRoute(path: '/scan', builder: (context, state) => const ScannerScreen()),
      GoRoute(path: '/scan/preview', builder: (context, state) => const PreviewScreen()),
      GoRoute(path: '/upload', builder: (context, state) => const UploadScreen()),
      GoRoute(path: '/processing', builder: (context, state) => const ProcessingScreen()),
      GoRoute(
        path: '/result/:id',
        builder: (context, state) => ResultScreen(docId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cabinet', builder: (context, state) => const CabinetListScreen()),
      GoRoute(
        path: '/cabinet/:id',
        builder: (context, state) =>
            CabinetDetailScreen(folderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/search', builder: (context, state) => const SearchScreen()),
      GoRoute(path: '/analytics', builder: (context, state) => const AnalyticsScreen()),
      GoRoute(path: '/admin', builder: (context, state) => const AdminScreen()),
      GoRoute(path: '/graph', builder: (context, state) => const GraphScreen()),
      GoRoute(
        path: '/review/:id',
        builder: (context, state) =>
            ReviewScreen(
              docId: state.pathParameters['id']!,
              isDuplicate: state.uri.queryParameters['dup'] == 'true',
            ),
      ),
    ],
  );

  // Re-evaluate router config when authState changes
  ref.listen(authProvider, (previous, next) {
    router.refresh();
  });

  return router;
});
