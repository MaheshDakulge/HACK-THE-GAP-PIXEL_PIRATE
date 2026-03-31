import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';

// Polls /upload/jobs/active every 4s. Uses Stream.periodic to avoid
// infinite while-true loops which cause BLASTBufferQueue frame overflow.
final activeJobsProvider = StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final dio = ref.watch(dioProvider);

  return Stream.periodic(const Duration(seconds: 4))
      .asyncMap((tick) async {
        try {
          final response = await dio.get('/upload/jobs/active');
          return List<Map<String, dynamic>>.from(response.data ?? []);
        } catch (e) {
          return <Map<String, dynamic>>[];
        }
      });
});
