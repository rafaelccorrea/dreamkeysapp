import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/utils/avatar_url_resolver.dart';

/// Empresa como a edição e o Perfil precisam — todos os campos do
/// `CompanyResponseDto`, sem o recorte enxuto do `Company` do seletor.
class CompanyAdminRecord {
  final String id;
  final String name;
  final String cnpj;
  final String corporateName;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String description;
  final double? latitude;
  final double? longitude;

  /// URL crua da logo (como o back devolve) — reenviada no PUT.
  final String? logoRaw;

  /// Logo resolvida para exibição (CDN absoluta).
  final String? logoUrl;
  final String? watermarkUrl;
  final bool isMatrix;
  final bool requireTwoFactor;
  final bool mobileAppAccessForAll;
  final String? createdAt;

  const CompanyAdminRecord({
    required this.id,
    required this.name,
    this.cnpj = '',
    this.corporateName = '',
    this.email = '',
    this.phone = '',
    this.address = '',
    this.city = '',
    this.state = '',
    this.zipCode = '',
    this.description = '',
    this.latitude,
    this.longitude,
    this.logoRaw,
    this.logoUrl,
    this.watermarkUrl,
    this.isMatrix = false,
    this.requireTwoFactor = false,
    this.mobileAppAccessForAll = false,
    this.createdAt,
  });

  static String _s(dynamic v) => v?.toString().trim() ?? '';

  static double? _d(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static bool _b(dynamic v) => v == true || v == 'true' || v == 1;

  factory CompanyAdminRecord.fromJson(Map<String, dynamic> json) {
    final rawLogo = _s(json['logo']).isNotEmpty
        ? _s(json['logo'])
        : _s(json['logoUrl']);
    final rawWatermark = _s(json['watermark']);
    return CompanyAdminRecord(
      id: _s(json['id']),
      name: _s(json['name']),
      cnpj: _s(json['cnpj']),
      corporateName: _s(json['corporateName']),
      email: _s(json['email']),
      phone: _s(json['phone']),
      address: _s(json['address']),
      city: _s(json['city']),
      state: _s(json['state']),
      zipCode: _s(json['zipCode']),
      description: _s(json['description']),
      latitude: _d(json['latitude']),
      longitude: _d(json['longitude']),
      logoRaw: rawLogo.isEmpty ? null : rawLogo,
      logoUrl: rawLogo.isEmpty ? null : AvatarUrlResolver.resolve(rawLogo),
      watermarkUrl: rawWatermark.isEmpty
          ? null
          : AvatarUrlResolver.resolve(rawWatermark),
      isMatrix: _b(json['isMatrix']),
      // Mesmos aliases que o ProfilePage do web lê.
      requireTwoFactor: _b(json['requireTwoFactor']) ||
          _b(json['require_2fa']) ||
          _b(json['totpRequired']),
      mobileAppAccessForAll: _b(json['mobileAppAccessForAll']) ||
          _b(json['mobile_app_access_for_all']),
      createdAt: _s(json['createdAt']).isNotEmpty
          ? _s(json['createdAt'])
          : (_s(json['created_at']).isEmpty ? null : _s(json['created_at'])),
    );
  }
}

/// Administração da empresa (admin/master) — paridade com `companyApi`,
/// `companyWatermarkService` e `settingsApi` do imobx-front:
///   • PUT  /companies/:id                 (EditCompanyPage)
///   • GET  /companies/geocode             (buscar coordenadas)
///   • POST /companies/:id/upload-logo     (multipart, campo `file`)
///   • POST /companies/:id/upload-watermark (multipart PNG, campo `file`)
///   • DELETE /companies/:id/watermark
///   • PATCH /companies/require-2fa        (X-Company-ID = empresa alvo)
///   • PATCH /companies/app-access-for-all (X-Company-ID = empresa alvo)
class CompanyAdminService {
  CompanyAdminService._();

  static final CompanyAdminService instance = CompanyAdminService._();
  final ApiService _api = ApiService.instance;

  // Endpoints privados da feature (fiação central fica fora daqui).
  static const String _companies = '/companies';
  static String _companyById(String id) => '/companies/$id';
  static const String _geocode = '/companies/geocode';
  static String _uploadLogo(String id) => '/companies/$id/upload-logo';
  static String _uploadWatermark(String id) =>
      '/companies/$id/upload-watermark';
  static String _watermark(String id) => '/companies/$id/watermark';
  static const String _require2fa = '/companies/require-2fa';
  static const String _appAccessForAll = '/companies/app-access-for-all';

  /// Lista completa das empresas do usuário (GET /companies), com os
  /// campos de configuração que o Perfil precisa.
  Future<ApiResponse<List<CompanyAdminRecord>>> listCompanies() async {
    try {
      final res = await _api.get<dynamic>(_companies);
      if (res.success && res.data is List) {
        final list = (res.data as List)
            .whereType<Map>()
            .map((e) => CompanyAdminRecord.fromJson(
                  Map<String, dynamic>.from(e),
                ))
            .toList();
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar empresas',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] listCompanies: $e');
      return ApiResponse.error(
        message: 'Erro ao carregar empresas',
        statusCode: 0,
      );
    }
  }

  Future<ApiResponse<CompanyAdminRecord>> getCompany(String id) async {
    try {
      final res = await _api.get<dynamic>(_companyById(id));
      if (res.success && res.data is Map) {
        return ApiResponse.success(
          data: CompanyAdminRecord.fromJson(
            Map<String, dynamic>.from(res.data as Map),
          ),
          statusCode: res.statusCode,
        );
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao carregar empresa',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] getCompany: $e');
      return ApiResponse.error(
        message: 'Erro ao carregar empresa',
        statusCode: 0,
      );
    }
  }

  /// PUT /companies/:id — payload já montado pela página (mesmos nomes do
  /// `CreateCompanyDto`).
  Future<ApiResponse<void>> updateCompany(
    String id,
    Map<String, dynamic> payload,
  ) async {
    try {
      final res = await _api.put<dynamic>(_companyById(id), body: payload);
      if (res.success) {
        return ApiResponse.success(statusCode: res.statusCode);
      }
      return ApiResponse.error(
        message: res.message ?? 'Erro ao atualizar empresa',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] updateCompany: $e');
      return ApiResponse.error(
        message: 'Erro ao atualizar empresa',
        statusCode: 0,
      );
    }
  }

  /// GET /companies/geocode — devolve `null` quando o endereço não foi
  /// encontrado (o back responde 200 sem corpo útil).
  Future<ApiResponse<({double latitude, double longitude})?>> geocode({
    String? address,
    String? city,
    String? state,
    String? zipCode,
  }) async {
    final query = <String, String>{};
    if ((address ?? '').isNotEmpty) query['address'] = address!;
    if ((city ?? '').isNotEmpty) query['city'] = city!;
    if ((state ?? '').isNotEmpty) query['state'] = state!;
    if ((zipCode ?? '').isNotEmpty) query['zipCode'] = zipCode!;
    try {
      final res = await _api.get<dynamic>(_geocode, queryParameters: query);
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao buscar coordenadas',
          statusCode: res.statusCode,
          data: res.error,
        );
      }
      final data = res.data;
      if (data is Map) {
        final lat = CompanyAdminRecord._d(data['latitude']);
        final lng = CompanyAdminRecord._d(data['longitude']);
        if (lat != null && lng != null) {
          return ApiResponse.success(
            data: (latitude: lat, longitude: lng),
            statusCode: res.statusCode,
          );
        }
      }
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] geocode: $e');
      return ApiResponse.error(
        message: 'Erro ao buscar coordenadas',
        statusCode: 0,
      );
    }
  }

  /// POST /companies/:id/upload-logo — devolve a `logoUrl` gravada.
  Future<ApiResponse<String>> uploadLogo(String id, File file) {
    return _upload(
      endpoint: _uploadLogo(id),
      file: file,
      resultKey: 'logoUrl',
      fallbackError: 'Erro ao enviar a logo',
    );
  }

  /// POST /companies/:id/upload-watermark — só PNG (o back recusa o resto).
  Future<ApiResponse<String>> uploadWatermark(String id, File file) {
    return _upload(
      endpoint: _uploadWatermark(id),
      file: file,
      resultKey: 'watermarkUrl',
      fallbackError: 'Erro ao fazer upload da marca d\'água',
    );
  }

  Future<ApiResponse<void>> removeWatermark(String id) async {
    try {
      final res = await _api.delete<dynamic>(_watermark(id));
      if (res.success) return ApiResponse.success(statusCode: res.statusCode);
      return ApiResponse.error(
        message: res.message ?? 'Erro ao remover marca d\'água',
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] removeWatermark: $e');
      return ApiResponse.error(
        message: 'Erro ao remover marca d\'água',
        statusCode: 0,
      );
    }
  }

  /// PATCH /companies/require-2fa — a empresa alvo vai no `X-Company-ID`
  /// (igual ao `settingsApi.setCompanyRequire2FAFor` do web).
  Future<ApiResponse<void>> setRequireTwoFactor(
    String companyId,
    bool requireTwoFactor,
  ) {
    return _patchForCompany(
      endpoint: _require2fa,
      companyId: companyId,
      body: {'requireTwoFactor': requireTwoFactor},
      fallbackError: 'Erro ao salvar 2FA da empresa.',
    );
  }

  /// PATCH /companies/app-access-for-all — empresa alvo no `X-Company-ID`.
  Future<ApiResponse<void>> setMobileAppAccessForAll(
    String companyId,
    bool mobileAppAccessForAll,
  ) {
    return _patchForCompany(
      endpoint: _appAccessForAll,
      companyId: companyId,
      body: {'mobileAppAccessForAll': mobileAppAccessForAll},
      fallbackError: 'Erro ao salvar o acesso ao app da empresa.',
    );
  }

  Future<ApiResponse<void>> _patchForCompany({
    required String endpoint,
    required String companyId,
    required Map<String, dynamic> body,
    required String fallbackError,
  }) async {
    try {
      final res = await _api.patch<dynamic>(
        endpoint,
        body: body,
        headers: {'X-Company-ID': companyId},
      );
      if (res.success) return ApiResponse.success(statusCode: res.statusCode);
      return ApiResponse.error(
        message: res.message ?? fallbackError,
        statusCode: res.statusCode,
        data: res.error,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] $endpoint: $e');
      return ApiResponse.error(message: fallbackError, statusCode: 0);
    }
  }

  static MediaType _mediaTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return MediaType('image', 'png');
      case 'webp':
        return MediaType('image', 'webp');
      case 'svg':
        return MediaType('image', 'svg+xml');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  Future<ApiResponse<String>> _upload({
    required String endpoint,
    required File file,
    required String resultKey,
    required String fallbackError,
  }) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final request = http.MultipartRequest('POST', uri);
      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      request.headers.addAll(headers);
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: file.path.split('/').last.split('\\').last,
          contentType: _mediaTypeFor(file.path),
        ),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamed);
      dynamic body;
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = null;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final url = body is Map ? body[resultKey]?.toString() : null;
        return ApiResponse.success(data: url, statusCode: response.statusCode);
      }
      String message = fallbackError;
      if (body is Map) {
        final m = body['message'];
        if (m is List && m.isNotEmpty) {
          message = m.first.toString();
        } else if (m != null && m.toString().trim().isNotEmpty) {
          message = m.toString();
        }
      }
      return ApiResponse.error(
        message: message,
        statusCode: response.statusCode,
        data: body,
      );
    } catch (e) {
      debugPrint('[COMPANY_ADMIN] upload $endpoint: $e');
      return ApiResponse.error(message: fallbackError, statusCode: 0);
    }
  }
}
