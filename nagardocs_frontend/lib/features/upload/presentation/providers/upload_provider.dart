import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/dio_client.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum UploadStatus { idle, uploading, processing, done, error }

class UploadState {
  final UploadStatus status;
  final String? jobId;
  final String? documentId;
  final String? errorMessage;
  final double progress;
  final int currentStep;
  final Map<String, dynamic>? extractedData; // Full doc+fields from backend

  UploadState({
    required this.status,
    this.jobId,
    this.documentId,
    this.errorMessage,
    this.progress = 0.0,
    this.currentStep = 0,
    this.extractedData,
  });

  factory UploadState.initial() => UploadState(status: UploadStatus.idle);
}

final uploadProvider =
    NotifierProvider<UploadNotifier, UploadState>(UploadNotifier.new);

class UploadNotifier extends Notifier<UploadState> {
  CancelToken? _cancelToken;

  @override
  UploadState build() => UploadState.initial();

  Future<bool> uploadDocument(String filePath) async {
    // Reset any previous token
    _cancelToken?.cancel('Cancelled by user');
    _cancelToken = CancelToken();

    state = UploadState(status: UploadStatus.uploading, progress: 0.0);
    try {
      final dio = ref.read(dioProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
      });

      final response = await dio.post(
        '/upload',
        data: formData,
        cancelToken: _cancelToken,
        onSendProgress: (count, total) {
          if (total > 0 && (_cancelToken?.isCancelled == false)) {
            final fileProgress = count / total;
            // Cap upload progress at 15% of the total UI progress bar
            // so processing starts at 15%
            state = UploadState(
              status: UploadStatus.uploading,
              progress: fileProgress * 0.15,
              currentStep: 0,
            );
          }
        },
      );

      final jobId = response.data['job_id'] ?? response.data['id'];

      // Start processing phase
      state = UploadState(status: UploadStatus.processing, jobId: jobId, progress: 0.15, currentStep: 1);
      return true;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // User cancelled, don't show an error state
        state = UploadState.initial();
        return false;
      }
      state = UploadState(status: UploadStatus.error, errorMessage: e.message ?? e.toString());
      return false;
    } catch (e) {
      state = UploadState(status: UploadStatus.error, errorMessage: e.toString());
      return false;
    }
  }

  Future<void> pollStatus() async {
    if (state.jobId == null || _cancelToken?.isCancelled == true) return;
    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get('/upload/status/${state.jobId}', cancelToken: _cancelToken);
      final data = response.data as Map<String, dynamic>;

      final remoteStatus = data['status'] as String? ?? 'processing';
      final docId = data['document_id'] as String?;
      final step = (data['step'] as num?)?.toInt() ?? state.currentStep;
      final progressPct = (data['progress_pct'] as num?)?.toDouble() ?? (step / 5.0);
      final extractedData = data['extracted_data'] as Map<String, dynamic>?;

      if (remoteStatus == 'done') {
        state = UploadState(
          status: UploadStatus.done,
          jobId: state.jobId,
          documentId: docId,
          progress: 1.0,
          currentStep: 5,
          extractedData: extractedData,
          errorMessage: data['error_message'],
        );
      } else if (remoteStatus == 'failed') {
        state = UploadState(
          status: UploadStatus.error,
          errorMessage: data['error_message'] ?? 'Processing failed',
        );
      } else {
        state = UploadState(
          status: UploadStatus.processing,
          jobId: state.jobId,
          currentStep: step.clamp(0, 5),
          progress: progressPct.clamp(0.0, 1.0),
        );
      }
    } on DioException catch (e) {
      // Ignore cancel exceptions
      if (CancelToken.isCancel(e)) return;
    } catch (e) {
      // Don't mark as error on a single poll failure — keep retrying
      // state stays as processing
    }
  }

  void reset() {
    _cancelToken?.cancel('Cancelled by user');
    state = UploadState.initial();
  }

  Future<void> uploadMultipleDocuments(List<String> filePaths) async {
    final dio = ref.read(dioProvider);
    // Execute sequentially in the background
    for (final path in filePaths) {
      try {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(path),
        });
        await dio.post('/upload', data: formData);
      } catch (e) {
        // Suppress errors for background batch uploads
        // They can be tracked in backend logs or a future bulk error view
        debugPrint('Background upload error for $path: $e');
      }
    }
  }
}
