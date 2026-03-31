import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../../core/network/dio_client.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

/// Exposes the stored user id (set after successful login)
final userIdProvider = FutureProvider<String?>((ref) async {
  const storage = FlutterSecureStorage();
  return storage.read(key: 'auth_user_id');
});

enum AuthStatus { initial, loading, authenticated, error }

class AuthState {
  final AuthStatus status;
  final String? errorMessage;
  final String role; // 'user' or 'admin'

  AuthState({required this.status, this.errorMessage, this.role = 'user'});

  factory AuthState.initial() => AuthState(status: AuthStatus.initial);
  factory AuthState.loading() => AuthState(status: AuthStatus.loading);
  factory AuthState.authenticated(String role) =>
      AuthState(status: AuthStatus.authenticated, role: role);
  factory AuthState.error(String msg) =>
      AuthState(status: AuthStatus.error, errorMessage: msg);

  bool get isAdmin => role == 'admin';
}

class AuthNotifier extends Notifier<AuthState> {
  final _storage = const FlutterSecureStorage();

  @override
  AuthState build() {
    _init();
    return AuthState.initial();
  }

  Future<void> _init() async {
    final token = await _storage.read(key: 'auth_token');
    final role = await _storage.read(key: 'auth_role') ?? 'user';
    if (token != null) {
      state = AuthState.authenticated(role);
    }
  }

  Future<bool> login(String email, String password, String deptCode) async {
    state = AuthState.loading();
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });

      final token = response.data['access_token'];
      if (token != null) {
        final role = response.data['role'] ?? 'user';
        
        // Decode the JWT to get the user ID (stored in 'sub')
        String? userId;
        try {
          final decodedToken = JwtDecoder.decode(token);
          userId = decodedToken['sub'] as String?;
        } catch (_) {}

        await _storage.write(key: 'auth_token', value: token);
        await _storage.write(key: 'auth_role', value: role);
        if (userId != null) {
          await _storage.write(key: 'auth_user_id', value: userId);
        }
        state = AuthState.authenticated(role);
        return true;
      }
      state = AuthState.error('Invalid credentials');
      return false;
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg;
      if (data is Map) {
        msg = data['detail'] ?? 'Network Error: Could not connect to backend';
      } else {
        msg = 'Network Error: Could not connect to backend';
      }
      state = AuthState.error(msg);
      return false;
    } catch (e) {
      state = AuthState.error('An unexpected error occurred.');
      return false;
    }
  }

  Future<bool> register(String name, String email, String password, String deptId) async {
    state = AuthState.loading();
    try {
      final dio = ref.read(dioProvider);

      final Map<String, dynamic> data = {
        'name': name,
        'email': email,
        'password': password,
      };

      // Supabase expects a UUID for department_id
      if (deptId.isNotEmpty && deptId.length > 20) {
        data['department_id'] = deptId;
      }

      await dio.post('/auth/signup', data: data);

      state = AuthState.initial();
      return true;
    } on DioException catch (e) {
      final data = e.response?.data;
      String msg;
      if (data is Map) {
        msg = data['detail'] ?? 'Registration failed or account exists.';
      } else {
        msg = 'Registration failed or account exists.';
      }
      state = AuthState.error(msg);
      return false;
    } catch (e) {
      state = AuthState.error('Unexpected error occurred.');
      return false;
    }
  }

  Future<void> logout() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_role');
    await _storage.delete(key: 'auth_user_id');
    state = AuthState.initial();
  }
}
