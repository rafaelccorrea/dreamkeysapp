import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../models/leads_export_models.dart';

/// Serviço de Backups / Exportação geral de leads — consome
/// `/kanban/leads-export-jobs` e `/kanban/leads-export-backups`
/// (paridade com `leadsExportApi` do imobx-front). Tudo requer `backup:view`.
class LeadsExportService {
  LeadsExportService._();

  static final LeadsExportService instance = LeadsExportService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados da feature.
  static const String _jobs = '/kanban/leads-export-jobs';
  static String _jobById(String id) => '/kanban/leads-export-jobs/$id';
  static String _jobDownload(String id) =>
      '/kanban/leads-export-jobs/$id/download';
  static const String _backups = '/kanban/leads-export-backups';
  static String _backupDownload(String id) =>
      '/kanban/leads-export-backups/$id/download';
  static String _backupById(String id) => '/kanban/leads-export-backups/$id';
  static String _backupRerun(String id) =>
      '/kanban/leads-export-backups/$id/rerun';

  /// `POST /kanban/leads-export-jobs` — enfileira uma exportação.
  Future<ApiResponse<String>> createJob(LeadsExportDraft draft) async {
    try {
      final response = await _api.post<dynamic>(_jobs, body: draft.toPayload());
      if (response.success) {
        final raw = response.data;
        final jobId = raw is Map ? raw['jobId']?.toString() ?? '' : '';
        return ApiResponse.success(
          data: jobId,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Não foi possível enfileirar a exportação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] createJob: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /kanban/leads-export-jobs` — meus jobs (mais recentes primeiro).
  Future<ApiResponse<List<LeadsExportJob>>> listMyJobs() async {
    try {
      final response = await _api.get<dynamic>(_jobs);
      if (response.success) {
        final raw = response.data;
        final list = raw is List
            ? raw
                .whereType<Map>()
                .map((e) =>
                    LeadsExportJob.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : <LeadsExportJob>[];
        return ApiResponse.success(
          data: list,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar exportações',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] listMyJobs: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /kanban/leads-export-jobs/:id` — cancela um job vivo.
  Future<ApiResponse<bool>> cancelJob(String jobId) async {
    try {
      final response = await _api.delete<dynamic>(_jobById(jobId));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao cancelar exportação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] cancelJob: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /kanban/leads-export-backups` — backups persistidos (60 dias).
  Future<ApiResponse<LeadsExportBackupList>> listBackups({
    String scope = 'mine',
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final response = await _api.get<Map<String, dynamic>>(
        _backups,
        queryParameters: {
          'scope': scope,
          'limit': '$limit',
          'offset': '$offset',
        },
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: LeadsExportBackupList.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar backups',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] listBackups: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `DELETE /kanban/leads-export-backups/:id` — apaga um backup.
  Future<ApiResponse<bool>> deleteBackup(String backupId) async {
    try {
      final response = await _api.delete<dynamic>(_backupById(backupId));
      if (response.success) {
        return ApiResponse.success(data: true, statusCode: response.statusCode);
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao apagar backup',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] deleteBackup: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `POST /kanban/leads-export-backups/:id/rerun` — repete com os mesmos filtros.
  Future<ApiResponse<String>> rerunBackup(String backupId) async {
    try {
      final response = await _api.post<dynamic>(_backupRerun(backupId));
      if (response.success) {
        final raw = response.data;
        final jobId = raw is Map ? raw['jobId']?.toString() ?? '' : '';
        return ApiResponse.success(
          data: jobId,
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao repetir exportação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] rerunBackup: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Baixa o arquivo de um **job** concluído como bytes.
  Future<ApiResponse<({Uint8List bytes, String fileName})>> downloadJobFile(
    String jobId, {
    String? fallbackName,
  }) =>
      _downloadFile(_jobDownload(jobId), fallbackName: fallbackName);

  /// Baixa o arquivo de um **backup** persistido como bytes.
  Future<ApiResponse<({Uint8List bytes, String fileName})>> downloadBackupFile(
    String backupId, {
    String? fallbackName,
  }) =>
      _downloadFile(_backupDownload(backupId), fallbackName: fallbackName);

  /// GET binário com os mesmos headers do interceptor (Authorization +
  /// X-Company-ID) — mesmo padrão do download de PDF das propostas.
  Future<ApiResponse<({Uint8List bytes, String fileName})>> _downloadFile(
    String endpoint, {
    String? fallbackName,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      headers['Accept'] = '*/*';

      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 90));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse.success(
          data: (
            bytes: res.bodyBytes,
            fileName: _fileNameFromDisposition(
              res.headers['content-disposition'],
              fallbackName ?? 'leads_export.xlsx',
            ),
          ),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: 'Erro ao baixar arquivo (${res.statusCode})',
        statusCode: res.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [LEADS_EXPORT] download: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Extrai o nome do `Content-Disposition` (paridade com o helper do web).
  static String _fileNameFromDisposition(String? disposition, String fallback) {
    if (disposition == null || disposition.isEmpty) return fallback;
    final match = RegExp(
      'filename\\*?=(?:UTF-8\'\')?"?([^";]+)',
      caseSensitive: false,
    ).firstMatch(disposition);
    final raw = match?.group(1)?.replaceAll('"', '').trim();
    if (raw == null || raw.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
}
