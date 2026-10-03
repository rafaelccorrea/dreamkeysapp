import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../../shared/services/property_service.dart';
import '../../../shared/utils/avatar_url_resolver.dart';

// ─── Modelos ────────────────────────────────────────────────────────────────

/// Arquivo que veio do servidor (foto, PDF, ZIP), pronto para compartilhar
/// ou salvar no aparelho.
class PropertyDownloadedFile {
  const PropertyDownloadedFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
  });

  final Uint8List bytes;

  /// Nome sugerido pelo servidor (`Content-Disposition`) ou o de reserva.
  final String fileName;

  /// Tipo do conteúdo (`application/pdf`, `application/zip`, `image/jpeg`…).
  final String mimeType;

  int get size => bytes.length;

  bool get isZip =>
      mimeType.contains('zip') || fileName.toLowerCase().endsWith('.zip');

  bool get isPdf =>
      mimeType.contains('pdf') || fileName.toLowerCase().endsWith('.pdf');

  bool get isImage => mimeType.startsWith('image/');
}

/// Uma pessoa da equipe que abriu a ficha — item de `viewers` do
/// `GET /properties/:id/views` (agregado por usuário).
class PropertyViewer {
  const PropertyViewer({
    required this.userId,
    this.userName,
    this.userEmail,
    this.userRole,
    this.avatar,
    this.visitCount = 0,
    this.totalViews = 0,
    this.firstViewedAt,
    this.lastViewedAt,
  });

  final String userId;
  final String? userName;
  final String? userEmail;

  /// Papel cru (`user`, `manager`, `admin`, `master`…).
  final String? userRole;
  final String? avatar;

  /// Visitas (sessões) distintas.
  final int visitCount;

  /// Total de aberturas da ficha (somando as visitas).
  final int totalViews;
  final DateTime? firstViewedAt;
  final DateTime? lastViewedAt;

  factory PropertyViewer.fromJson(Map<String, dynamic> json) {
    return PropertyViewer(
      userId: _text(json['userId']) ?? '',
      userName: _text(json['userName']),
      userEmail: _text(json['userEmail']),
      userRole: _text(json['userRole']),
      avatar: AvatarUrlResolver.resolve(_text(json['avatar'])),
      visitCount: _int(json['visitCount']),
      totalViews: _int(json['totalViews']),
      firstViewedAt: _date(json['firstViewedAt']),
      lastViewedAt: _date(json['lastViewedAt']),
    );
  }
}

/// Resposta de `GET /properties/:id/views` — quem da equipe viu a ficha.
class PropertyViewsSummary {
  const PropertyViewsSummary({
    this.totalVisits = 0,
    this.totalViews = 0,
    this.uniqueViewers = 0,
    this.viewers = const <PropertyViewer>[],
  });

  static const PropertyViewsSummary empty = PropertyViewsSummary();

  final int totalVisits;
  final int totalViews;
  final int uniqueViewers;

  /// Por usuário, do acesso mais recente para o mais antigo (ordem da API).
  final List<PropertyViewer> viewers;

  /// Mesma condição do web (`data.uniqueViewers > 0`).
  bool get hasData => uniqueViewers > 0;

  factory PropertyViewsSummary.fromJson(Map<String, dynamic> json) {
    final viewers = _asList(json['viewers'])
        .map(_asMap)
        .whereType<Map<String, dynamic>>()
        .map(PropertyViewer.fromJson)
        .where((v) => v.userId.isNotEmpty)
        .toList();
    return PropertyViewsSummary(
      totalVisits: _int(json['totalVisits']),
      totalViews: _int(json['totalViews']),
      uniqueViewers: json.containsKey('uniqueViewers')
          ? _int(json['uniqueViewers'])
          : viewers.length,
      viewers: viewers,
    );
  }
}

/// Versão guardada da ficha (retrato tirado ANTES de uma alteração) — item
/// de `GET /properties/:id/revisions`.
class PropertyRevision {
  const PropertyRevision({
    required this.id,
    this.createdAt,
    this.createdByUserId,
    this.createdByName,
  });

  final String id;
  final DateTime? createdAt;
  final String? createdByUserId;

  /// Quem fez a alteração que gerou esta versão.
  final String? createdByName;

  factory PropertyRevision.fromJson(Map<String, dynamic> json) {
    final user = _asMap(json['createdByUser']);
    return PropertyRevision(
      id: _text(json['id']) ?? '',
      createdAt: _date(json['createdAt']),
      createdByUserId:
          _text(json['createdByUserId']) ?? _text(user?['id']),
      createdByName: _text(user?['name']),
    );
  }
}

/// Resultado de `POST /properties/:id/geocode-location`.
class PropertyGeocodeResult {
  const PropertyGeocodeResult({
    this.latitude,
    this.longitude,
    this.geocoded = false,
  });

  final double? latitude;
  final double? longitude;

  /// `false` quando o endereço não foi localizado.
  final bool geocoded;

  /// Mesma condição do web para aplicar as coordenadas no mapa.
  bool get hasCoords => geocoded && latitude != null && longitude != null;
}

/// Condomínio ou empreendimento vinculado ao imóvel, com os campos que a
/// ficha do web mostra (`Condominium`/`Empreendimento` do front).
class PropertyLinkedEntity {
  const PropertyLinkedEntity({
    required this.id,
    required this.name,
    this.description,
    this.address,
    this.street,
    this.number,
    this.complement,
    this.neighborhood,
    this.city,
    this.state,
    this.zipCode,
    this.phone,
    this.email,
    this.cnpj,
    this.website,
    this.isActive,
  });

  final String id;
  final String name;
  final String? description;
  final String? address;
  final String? street;
  final String? number;
  final String? complement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? zipCode;
  final String? phone;
  final String? email;
  final String? cnpj;
  final String? website;

  /// `null` quando a API não informou (a pílula Ativo/Inativo não aparece).
  final bool? isActive;

  factory PropertyLinkedEntity.fromJson(Map<String, dynamic> json) {
    return PropertyLinkedEntity(
      id: _text(json['id']) ?? '',
      name: _text(json['name']) ?? '',
      description: _text(json['description']),
      address: _text(json['address']),
      street: _text(json['street']),
      number: _text(json['number']),
      complement: _text(json['complement']),
      neighborhood: _text(json['neighborhood']) ?? _text(json['district']),
      city: _text(json['city']),
      state: _text(json['state']) ?? _text(json['uf']),
      zipCode: _text(json['zipCode']) ?? _text(json['zip_code']),
      phone: _text(json['phone']),
      email: _text(json['email']),
      cnpj: _text(json['cnpj']),
      website: _text(json['website']),
      isActive: _bool(json['isActive'] ?? json['is_active']),
    );
  }

  /// Endereço completo numa linha — `formatCondominiumAddress` do web
  /// ("Rua, 10, Bloco A · Centro · Cidade/UF · CEP 00000-000"); sem as
  /// partes, cai no `address` livre.
  String get fullAddress {
    final line1 = [street, number, complement]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final c = city ?? '';
    final s = state ?? '';
    final cityState = c.isNotEmpty && s.isNotEmpty
        ? '$c/$s'
        : (c.isNotEmpty ? c : s);
    final zip = zipCode ?? '';
    final line2 = [
      neighborhood ?? '',
      cityState,
      if (zip.isNotEmpty) 'CEP $zip',
    ].where((p) => p.trim().isNotEmpty).join(' · ');
    final composed = [line1, line2].where((p) => p.isNotEmpty).join(' · ');
    return composed.isNotEmpty ? composed : (address ?? '');
  }

  /// Linha curta do seletor — `formatCondominiumAddressLine` do web.
  String get pickerAddressLine {
    final streetPart = [street ?? address, number]
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .join(', ');
    final tail = [neighborhood, city, state]
        .whereType<String>()
        .where((p) => p.trim().isNotEmpty)
        .join(' · ');
    if (streetPart.isNotEmpty && tail.isNotEmpty) return '$streetPart · $tail';
    if (streetPart.isNotEmpty) return streetPart;
    if (tail.isNotEmpty) return tail;
    return address ?? '';
  }
}

/// Página da lista de condomínios/empreendimentos do seletor.
class PropertyLinkedEntityPage {
  const PropertyLinkedEntityPage({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
  });

  final List<PropertyLinkedEntity> items;
  final int page;
  final int totalPages;
  final int total;

  bool get hasMore => page < totalPages;
}

// ─── Serviço ────────────────────────────────────────────────────────────────

/// Chamadas da ficha do imóvel que a paridade web × app trouxe na onda 2:
/// visualizações da equipe, versões (restaurar), fotos (arquivo + registro
/// de download), autorização assinada, PDF da ficha de venda vinculada,
/// vitrine do site, condomínio/empreendimento, geolocalização e o
/// responsável principal de reserva. (Desvincular cliente fica com o
/// `ClientService.disassociateClientFromProperty`, que já existe.)
///
/// Nenhum método lança: toda falha volta no [ApiResponse] com o código HTTP
/// (0 = sem conexão, 408 = passou do teto de espera, -1 = falha local) e, em
/// `message`, só o que o servidor explicou — a tela descreve a causa pela
/// família do código (`pdkFailureCause`).
class PropertyDetailExtrasService {
  PropertyDetailExtrasService._();

  static final PropertyDetailExtrasService instance =
      PropertyDetailExtrasService._();

  final ApiService _api = ApiService.instance;

  /// Teto das escritas na ficha — o mesmo `PROPERTY_WRITE_TIMEOUT_MS` do web
  /// (5 min): cortar antes faria a tela dizer "falhou" com a mudança já
  /// aplicada.
  static const Duration propertyWriteTimeout = Duration(seconds: 300);

  /// Teto do PDF assinado da ficha de venda (o
  /// `SALE_FORMS_LONG_REQUEST_TIMEOUT_MS` do web).
  static const Duration saleFormPdfTimeout = Duration(seconds: 120);

  static const Duration _binaryTimeout = Duration(seconds: 90);

  // ─── Regras compartilhadas ────────────────────────────────────────────

  /// A regra de permissão do WEB (`usePermissionsOptimized.hasPermission`):
  /// master/admin passam em tudo; gestor passa só em `property:update` e
  /// `property:delete`; o resto depende da permissão EXPLÍCITA. O
  /// `hasPermission` do app libera gestor em tudo — use este nos gates da
  /// ficha que precisam bater com o web. Passe o papel e
  /// `ModuleAccessService.instance.userPermissionNames`.
  static bool webHasPermission({
    required String? role,
    required List<String> explicitPermissions,
    required String permission,
  }) {
    final r = role?.trim().toLowerCase() ?? '';
    if (r == 'master' || r == 'admin') return true;
    if (r == 'manager' &&
        (permission == 'property:update' || permission == 'property:delete')) {
      return true;
    }
    return explicitPermissions.contains(permission);
  }

  /// Gestão da empresa (`isManagementRole` do web): master, admin ou gestor.
  static bool isManagementRole(String? role) {
    final r = role?.trim().toLowerCase() ?? '';
    return r == 'master' || r == 'admin' || r == 'manager';
  }

  /// Coordenadas utilizáveis no mapa (`hasValidCoords` do web).
  static bool hasValidCoords(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return false;
    if (!latitude.isFinite || !longitude.isFinite) return false;
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
  }

  /// Há endereço bastante para geolocalizar (`hasAddressForGeocode` do
  /// web): cidade + UF + (rua, endereço, CEP ou bairro).
  static bool hasAddressForGeocode(Property property) {
    bool filled(String? v) => (v ?? '').trim().isNotEmpty;
    return filled(property.city) &&
        filled(property.state) &&
        (filled(property.street) ||
            filled(property.address) ||
            filled(property.zipCode) ||
            filled(property.neighborhood));
  }

  // ─── Visualizações da equipe ──────────────────────────────────────────

  /// `GET /properties/:id/views` — quem da equipe abriu a ficha e quando.
  /// Só gestor/admin/master (o back devolve 403 aos demais).
  Future<ApiResponse<PropertyViewsSummary>> getViews(String propertyId) async {
    try {
      final res = await _api.get<dynamic>('/properties/$propertyId/views');
      if (res.success) {
        final map = _unwrap(res.data);
        return ApiResponse.success(
          data: map == null
              ? PropertyViewsSummary.empty
              : PropertyViewsSummary.fromJson(map),
          statusCode: res.statusCode,
        );
      }
      return _fail<PropertyViewsSummary>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] views: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  // ─── Versões da ficha ─────────────────────────────────────────────────

  /// `GET /properties/:id/revisions?limit=` — versões guardadas antes de
  /// cada alteração, da mais recente para a mais antiga (padrão 50, máx.
  /// 200 — o mesmo teto do web).
  Future<ApiResponse<List<PropertyRevision>>> getRevisions(
    String propertyId, {
    int limit = 50,
  }) async {
    final lim = limit.clamp(1, 200);
    try {
      final res = await _api.get<dynamic>(
        '/properties/$propertyId/revisions',
        queryParameters: {'limit': '$lim'},
      );
      if (res.success) {
        final list = _asList(res.data)
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map(PropertyRevision.fromJson)
            .where((r) => r.id.isNotEmpty)
            .toList();
        return ApiResponse.success(data: list, statusCode: res.statusCode);
      }
      return _fail<List<PropertyRevision>>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] revisions: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// `POST /properties/:id/revisions/:revId/restore` — a ficha volta ao
  /// estado desta versão (com responsáveis/captadores quando constarem nela).
  /// Só admin, gestor ou master. `data` traz o imóvel restaurado quando o
  /// corpo foi legível; sucesso com `data` nulo = recarregue a ficha.
  Future<ApiResponse<Property>> restoreRevision(
    String propertyId,
    String revisionId,
  ) async {
    final res = await _sendJson(
      'POST',
      '/properties/$propertyId/revisions/$revisionId/restore',
      body: const <String, dynamic>{},
      timeout: propertyWriteTimeout,
      logTag: 'restore',
    );
    return _asPropertyResponse(res);
  }

  // ─── Fotos ────────────────────────────────────────────────────────────

  /// Bytes de uma foto da galeria: primeiro o proxy autenticado
  /// `GET /gallery/images/:id/file` (mesmo escopo de empresa), depois a URL
  /// pública da foto ([fallbackUrl]) — a mesma cascata do web. Falha com
  /// `statusCode` 404 quando a foto não está mais no armazenamento.
  Future<ApiResponse<PropertyDownloadedFile>> downloadGalleryImage(
    String imageId, {
    String? fallbackUrl,
  }) async {
    ApiResponse<PropertyDownloadedFile>? apiFailure;
    final id = imageId.trim();
    if (id.isNotEmpty) {
      final endpoint = '/gallery/images/$id/file';
      final res = await _getBinary(
        endpoint,
        fallbackName: 'foto',
        timeout: _binaryTimeout,
        accept: 'image/*, */*',
        logTag: 'gallery-file',
        nonFileIsMissing: true,
      );
      final file = res.data;
      if (res.success && file != null) {
        if (_looksLikeImage(file)) return res;
        apiFailure = ApiResponse.error(message: '', statusCode: 404);
      } else {
        apiFailure = res;
      }
    }

    final url = fallbackUrl?.trim() ?? '';
    if (url.startsWith('http')) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(_binaryTimeout);
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            response.bodyBytes.isNotEmpty) {
          final type = _mimeOf(
            response.headers['content-type'],
            response.bodyBytes,
          );
          final file = PropertyDownloadedFile(
            bytes: response.bodyBytes,
            fileName: 'foto.${extensionForMime(type)}',
            mimeType: type,
          );
          if (_looksLikeImage(file)) {
            return ApiResponse.success(
              data: file,
              statusCode: response.statusCode,
            );
          }
        }
        if (apiFailure == null || apiFailure.statusCode == 404) {
          return ApiResponse.error(message: '', statusCode: 404);
        }
      } on TimeoutException {
        return apiFailure ?? ApiResponse.error(message: '', statusCode: 408);
      } catch (e) {
        debugPrint('❌ [PROPERTY_EXTRAS] foto pela URL: $e');
      }
    }
    return apiFailure ?? ApiResponse.error(message: '', statusCode: 404);
  }

  /// `POST /properties/:id/track-download {kind, count}` — registra no
  /// histórico que alguém baixou fotos (`kind`: `single` para uma foto,
  /// `zip` para várias — os dois únicos valores que o back aceita). Melhor
  /// esforço, igual ao web: nunca atrapalha o download; devolve se gravou.
  Future<bool> trackImageDownload(
    String propertyId, {
    required String kind,
    int count = 1,
  }) async {
    try {
      final res = await _api.post<dynamic>(
        '/properties/$propertyId/track-download',
        body: {'kind': kind == 'zip' ? 'zip' : 'single', 'count': count},
      );
      return res.success;
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] track-download: $e');
      return false;
    }
  }

  // ─── Autorização do proprietário assinada ─────────────────────────────

  /// `GET /properties/:id/owner-authorization/signed-pdf` — o documento
  /// assinado (PDF, ou a imagem do físico validado). Nome do
  /// `Content-Disposition`; sem ele, `autorizacao_assinada.pdf` (o do web).
  Future<ApiResponse<PropertyDownloadedFile>>
      downloadOwnerAuthorizationSignedPdf(String propertyId) {
    return _getBinary(
      '/properties/$propertyId/owner-authorization/signed-pdf',
      fallbackName: 'autorizacao_assinada.pdf',
      timeout: _binaryTimeout,
      accept: 'application/pdf, image/*, application/json',
      logTag: 'owner-auth-pdf',
    );
  }

  /// `GET /hierarchy/accessible-users` — ids que o usuário logado alcança
  /// (ele + quem ele gerencia). É a regra do gestor no certificado.
  Future<ApiResponse<Set<String>>> getAccessibleUserIds() async {
    try {
      final res = await _api.get<dynamic>('/hierarchy/accessible-users');
      if (res.success) {
        final map = _unwrap(res.data);
        final ids = <String>{
          for (final raw in _asList(map?['accessibleUserIds']))
            if (_text(raw) != null) _text(raw)!,
        };
        return ApiResponse.success(data: ids, statusCode: res.statusCode);
      }
      return _fail<Set<String>>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] accessible-users: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  // ─── Ficha de venda vinculada ─────────────────────────────────────────

  /// `GET /sistema/fichas-venda/por-imovel/:propertyId/pdf-assinado` — o PDF
  /// assinado na Autentique da ficha finalizada; com mais de um documento o
  /// back manda um ZIP. Reservas de nome iguais às do web.
  Future<ApiResponse<PropertyDownloadedFile>> downloadLinkedSaleFormSignedPdf(
    String propertyId,
  ) async {
    final id = Uri.encodeComponent(propertyId);
    final res = await _getBinary(
      '/sistema/fichas-venda/por-imovel/$id/pdf-assinado',
      fallbackName: 'Ficha_imovel_${propertyId}_assinado.pdf',
      zipFallbackName: 'Ficha_imovel_${propertyId}_assinados.zip',
      timeout: saleFormPdfTimeout,
      accept: 'application/pdf, application/zip, application/json',
      logTag: 'sale-form-pdf',
    );
    final file = res.data;
    if (res.success && file != null && !file.isPdf && !file.isZip) {
      // Nem PDF nem ZIP: o web trata como falha ("Erro ao baixar PDF").
      return ApiResponse.error(message: '', statusCode: 500);
    }
    return res;
  }

  // ─── Vitrine do site ──────────────────────────────────────────────────

  /// `PATCH /properties/:id` só com as chaves da vitrine que mudaram —
  /// `isAvailableForSite`, `isFeatured`, `isSitePremiumLine` (os mesmos nomes
  /// do web). Tirar do site manda as três juntas (`false`): quem monta o
  /// patch é a aba (regra do web). Sucesso com `data` nulo = recarregue.
  Future<ApiResponse<Property>> updateSiteShowcase(
    String propertyId, {
    bool? isAvailableForSite,
    bool? isFeatured,
    bool? isSitePremiumLine,
  }) async {
    final body = <String, dynamic>{
      if (isAvailableForSite != null) 'isAvailableForSite': isAvailableForSite,
      if (isFeatured != null) 'isFeatured': isFeatured,
      if (isSitePremiumLine != null) 'isSitePremiumLine': isSitePremiumLine,
    };
    if (body.isEmpty) {
      return ApiResponse.error(message: '', statusCode: -1);
    }
    final res = await _sendJson(
      'PATCH',
      '/properties/$propertyId',
      body: body,
      timeout: propertyWriteTimeout,
      logTag: 'site-showcase',
    );
    return _asPropertyResponse(res);
  }

  /// Mostra/oculta UMA foto no site público — `PUT /gallery/:id
  /// { showOnPublicSite }` (`UpdateImageDto`; a rota é PUT, não PATCH). Foto
  /// oculta segue no CRM e não conta para as 5 fotos de publicação.
  Future<ApiResponse<void>> setImageShowOnPublicSite(
    String imageId, {
    required bool show,
  }) async {
    final res = await _sendJson(
      'PUT',
      '/gallery/$imageId',
      body: {'showOnPublicSite': show},
      timeout: const Duration(seconds: 30),
      logTag: 'gallery-site-visibility',
    );
    if (res.success) {
      return ApiResponse.success(data: null, statusCode: res.statusCode);
    }
    return ApiResponse.error(
      message: res.message ?? '',
      statusCode: res.statusCode,
      data: res.error,
    );
  }

  /// A aba "Site" existe para esta empresa? `true` só quando a esteira de
  /// aprovação está DESLIGADA (`requireApprovalToPublishOnSite` e
  /// `requireApprovalToBeAvailable` falsos). Falha na leitura = esteira
  /// ligada (aba escondida), exatamente como o web.
  Future<bool> isApprovalWorkflowOff() async {
    try {
      final res =
          await PropertyService.instance.getPropertyApprovalSettingsActive();
      final cfg = res.data;
      if (!res.success || cfg == null) return false;
      return !cfg.requireApprovalToPublishOnSite &&
          !cfg.requireApprovalToBeAvailable;
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] approval-settings: $e');
      return false;
    }
  }

  // ─── Condomínio e empreendimento ──────────────────────────────────────

  /// `GET /condominiums/:id` — leitura completa para a ficha.
  Future<ApiResponse<PropertyLinkedEntity>> getCondominium(String id) =>
      _getEntity('/condominiums/$id', 'condominium');

  /// `GET /empreendimentos/:id` — leitura completa para a ficha.
  Future<ApiResponse<PropertyLinkedEntity>> getEmpreendimento(String id) =>
      _getEntity('/empreendimentos/$id', 'empreendimento');

  /// Lista do seletor "Alterar vínculo" — só ativos, por nome, busca no
  /// servidor, 25 por página (o `CondominiumSelector` do web).
  Future<ApiResponse<PropertyLinkedEntityPage>> listCondominiums({
    int page = 1,
    int limit = 25,
    String? search,
  }) =>
      _listEntities('/condominiums', page: page, limit: limit, search: search);

  /// Lista do seletor "Alterar vínculo" de empreendimentos (mesmas regras).
  Future<ApiResponse<PropertyLinkedEntityPage>> listEmpreendimentos({
    int page = 1,
    int limit = 25,
    String? search,
  }) =>
      _listEntities('/empreendimentos',
          page: page, limit: limit, search: search);

  /// `PATCH /properties/:id {condominiumId}` — `null` desfaz o vínculo
  /// (o "Remover condomínio" do seletor do web).
  Future<ApiResponse<Property>> linkCondominium(
    String propertyId,
    String? condominiumId,
  ) async {
    final res = await _sendJson(
      'PATCH',
      '/properties/$propertyId',
      body: {'condominiumId': _nullIfEmpty(condominiumId)},
      timeout: propertyWriteTimeout,
      logTag: 'link-condominium',
    );
    return _asPropertyResponse(res);
  }

  /// `PATCH /properties/:id {empreendimentoId}` — `null` desfaz o vínculo.
  Future<ApiResponse<Property>> linkEmpreendimento(
    String propertyId,
    String? empreendimentoId,
  ) async {
    final res = await _sendJson(
      'PATCH',
      '/properties/$propertyId',
      body: {'empreendimentoId': _nullIfEmpty(empreendimentoId)},
      timeout: propertyWriteTimeout,
      logTag: 'link-empreendimento',
    );
    return _asPropertyResponse(res);
  }

  // ─── Localização ──────────────────────────────────────────────────────

  /// `POST /properties/:id/geocode-location` — busca latitude/longitude pelo
  /// endereço e grava no imóvel. `geocoded == false` = endereço não achado
  /// (o web avisa só quando foi pedido à mão).
  Future<ApiResponse<PropertyGeocodeResult>> geocodeLocation(
    String propertyId,
  ) async {
    try {
      final res =
          await _api.post<dynamic>('/properties/$propertyId/geocode-location');
      if (res.success) {
        final map = _unwrap(res.data);
        return ApiResponse.success(
          data: PropertyGeocodeResult(
            latitude: _double(map?['latitude']),
            longitude: _double(map?['longitude']),
            geocoded: _bool(map?['geocoded']) ?? false,
          ),
          statusCode: res.statusCode,
        );
      }
      return _fail<PropertyGeocodeResult>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] geocode: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  // ─── Responsável de reserva ───────────────────────────────────────────

  /// Responsável principal quando o `GET /properties/:id` não trouxe a lista
  /// `responsibles` — mesma cascata do web (W:1198-1245): `GET
  /// /admin/users/:id` e, se falhar, `GET /admin/users/:id/basic`. `null`
  /// quando nenhum respondeu (a seção segue escondida, como no web).
  Future<PropertyResponsible?> fetchMainResponsible(String userId) async {
    final id = userId.trim();
    if (id.isEmpty) return null;
    final endpoints = <String>['/admin/users/$id', '/admin/users/$id/basic'];
    for (final endpoint in endpoints) {
      try {
        final res = await _api.get<dynamic>(endpoint);
        if (!res.success) continue;
        final map = _unwrap(res.data);
        if (map == null) continue;
        final person = PropertyResponsible.fromJson(map);
        if (person.id.isEmpty) continue;
        return person;
      } catch (e) {
        debugPrint('❌ [PROPERTY_EXTRAS] responsável ($endpoint): $e');
      }
    }
    return null;
  }

  // ─── Utilidades públicas ──────────────────────────────────────────────

  /// Extensão de arquivo para um tipo de imagem/documento.
  static String extensionForMime(String mime) {
    final m = mime.toLowerCase();
    if (m.contains('png')) return 'png';
    if (m.contains('webp')) return 'webp';
    if (m.contains('gif')) return 'gif';
    if (m.contains('heic')) return 'heic';
    if (m.contains('pdf')) return 'pdf';
    if (m.contains('zip')) return 'zip';
    return 'jpg';
  }

  // ─── Internos ─────────────────────────────────────────────────────────

  Future<ApiResponse<PropertyLinkedEntity>> _getEntity(
    String endpoint,
    String logTag,
  ) async {
    try {
      final res = await _api.get<dynamic>(endpoint);
      if (res.success) {
        final map = _unwrap(res.data);
        final entity = map == null ? null : PropertyLinkedEntity.fromJson(map);
        if (entity == null || entity.id.isEmpty) {
          return ApiResponse.error(message: '', statusCode: 500);
        }
        return ApiResponse.success(data: entity, statusCode: res.statusCode);
      }
      return _fail<PropertyLinkedEntity>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] $logTag: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  Future<ApiResponse<PropertyLinkedEntityPage>> _listEntities(
    String endpoint, {
    required int page,
    required int limit,
    String? search,
  }) async {
    try {
      final params = <String, String>{
        'page': '$page',
        'limit': '$limit',
        'isActive': 'true',
        'sortBy': 'name',
        'sortOrder': 'ASC',
      };
      final s = search?.trim() ?? '';
      if (s.isNotEmpty) params['search'] = s;
      final res = await _api.get<dynamic>(endpoint, queryParameters: params);
      if (res.success) {
        final root = _asMap(res.data);
        final items = _asList(res.data)
            .map(_asMap)
            .whereType<Map<String, dynamic>>()
            .map(PropertyLinkedEntity.fromJson)
            // O seletor do web descarta os inativos mesmo com o filtro.
            .where((e) => e.id.isNotEmpty && e.isActive != false)
            .toList();
        final totalPages = _int(root?['totalPages'], fallback: 1);
        return ApiResponse.success(
          data: PropertyLinkedEntityPage(
            items: items,
            page: _int(root?['page'], fallback: page),
            totalPages: totalPages < 1 ? 1 : totalPages,
            total: _int(root?['total'], fallback: items.length),
          ),
          statusCode: res.statusCode,
        );
      }
      return _fail<PropertyLinkedEntityPage>(res);
    } catch (e) {
      debugPrint('❌ [PROPERTY_EXTRAS] lista $endpoint: $e');
      return ApiResponse.error(message: '', statusCode: -1, data: e);
    }
  }

  /// GET binário (fora do `ApiService`, que só fala JSON): token com folga,
  /// os cabeçalhos do interceptor do web e o nome do `Content-Disposition`.
  /// [nonFileIsMissing]: 2xx sem arquivo conta como "não está no
  /// armazenamento" (404) — a leitura do web para as fotos da galeria.
  Future<ApiResponse<PropertyDownloadedFile>> _getBinary(
    String endpoint, {
    required String fallbackName,
    String? zipFallbackName,
    required Duration timeout,
    required String accept,
    required String logTag,
    bool nonFileIsMissing = false,
  }) async {
    try {
      await _api.garantirTokenFresco(margemSegundos: 120);
      final headers = await _api.buildOutboundHeaders(
        endpoint: endpoint,
        excludeContentType: true,
      );
      headers['Accept'] = accept;
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final res = await http.get(uri, headers: headers).timeout(timeout);
      final rawType = (res.headers['content-type'] ?? '').toLowerCase();
      final ok = res.statusCode >= 200 && res.statusCode < 300;
      if (ok && res.statusCode != 204 && res.bodyBytes.isNotEmpty &&
          !rawType.contains('application/json') &&
          !rawType.contains('text/html')) {
        final type = _mimeOf(rawType, res.bodyBytes);
        final isZip = type.contains('zip');
        final name = fileNameFromDisposition(
          res.headers['content-disposition'],
          isZip && zipFallbackName != null ? zipFallbackName : fallbackName,
        );
        return ApiResponse.success(
          data: PropertyDownloadedFile(
            bytes: res.bodyBytes,
            fileName: name,
            mimeType: type,
          ),
          statusCode: res.statusCode,
        );
      }
      if (ok) {
        // 2xx sem arquivo (vazio, 204 ou JSON): falha do servidor — ou foto
        // que não está mais no armazenamento.
        final missing = nonFileIsMissing ||
            res.statusCode == 204 ||
            res.bodyBytes.isEmpty;
        return ApiResponse.error(
          message: _messageOf(_decode(res.bodyBytes)) ?? '',
          statusCode: missing ? 404 : 500,
        );
      }
      return ApiResponse.error(
        message: _messageOf(_decode(res.bodyBytes)) ?? '',
        statusCode: res.statusCode,
      );
    } on TimeoutException {
      return ApiResponse.error(message: '', statusCode: 408);
    } on SocketException catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag sem conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } on http.ClientException catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag: $e');
      return ApiResponse.error(
        message: _companyMessage(e),
        statusCode: -1,
        data: e,
      );
    }
  }

  /// Escrita com teto de espera próprio (o `ApiService` corta em 30 s).
  /// Mesmos cabeçalhos do interceptor do web (token com folga +
  /// X-Company-ID).
  Future<ApiResponse<dynamic>> _sendJson(
    String method,
    String endpoint, {
    Object? body,
    required Duration timeout,
    required String logTag,
  }) async {
    try {
      await _api.garantirTokenFresco(margemSegundos: 120);
      final headers = await _api.buildOutboundHeaders(endpoint: endpoint);
      final uri = Uri.parse('${ApiConstants.baseApiUrl}$endpoint');
      final encoded = body == null ? null : jsonEncode(body);
      final http.Response res;
      switch (method) {
        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'DELETE':
          res = await http
              .delete(uri, headers: headers, body: encoded)
              .timeout(timeout);
        case 'PUT':
          res = await http
              .put(uri, headers: headers, body: encoded)
              .timeout(timeout);
        default:
          res = await http
              .post(uri, headers: headers, body: encoded)
              .timeout(timeout);
      }
      final decoded = _decode(res.bodyBytes);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return ApiResponse.success(data: decoded, statusCode: res.statusCode);
      }
      return ApiResponse.error(
        message: _messageOf(decoded) ?? '',
        statusCode: res.statusCode,
        data: decoded,
      );
    } on TimeoutException {
      return ApiResponse.error(message: '', statusCode: 408);
    } on SocketException catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag sem conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } on http.ClientException catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag conexão: $e');
      return ApiResponse.error(message: '', statusCode: 0);
    } catch (e) {
      debugPrint('[PROPERTY_EXTRAS] $logTag: $e');
      return ApiResponse.error(
        message: _companyMessage(e),
        statusCode: -1,
        data: e,
      );
    }
  }

  /// Resposta de escrita → imóvel (quando o corpo trouxe um legível).
  ApiResponse<Property> _asPropertyResponse(ApiResponse<dynamic> res) {
    if (!res.success) {
      return ApiResponse.error(
        message: res.message ?? '',
        statusCode: res.statusCode,
        data: res.error,
      );
    }
    Property? property;
    try {
      final root = _asMap(res.data);
      final payload = root == null
          ? null
          : (_asMap(root['property']) ??
              (root['id'] != null ? root : _asMap(root['data'])));
      if (payload != null && (payload['id']?.toString() ?? '').isNotEmpty) {
        property = Property.fromJson(payload);
      }
    } catch (e) {
      debugPrint('[PROPERTY_EXTRAS] imóvel da resposta: $e');
    }
    return ApiResponse.success(data: property, statusCode: res.statusCode);
  }

  ApiResponse<T> _fail<T>(ApiResponse<dynamic> res) {
    return ApiResponse<T>.error(
      message: res.message ?? '',
      statusCode: res.statusCode,
      data: res.error,
    );
  }

  /// Nome do `Content-Disposition` (RFC 5987 primeiro, depois entre aspas,
  /// depois simples) — `filenameFromContentDisposition` do web.
  static String fileNameFromDisposition(String? header, String fallback) {
    final raw = header ?? '';
    if (raw.isEmpty) return fallback;
    final star = RegExp("filename\\*=UTF-8''([^;\\n]+)", caseSensitive: false)
        .firstMatch(raw);
    if (star != null) {
      final v = star.group(1)!.trim();
      try {
        return Uri.decodeComponent(v);
      } catch (_) {
        return v;
      }
    }
    final quoted =
        RegExp('filename="([^"]+)"', caseSensitive: false).firstMatch(raw);
    if (quoted != null) return quoted.group(1)!.trim();
    final plain =
        RegExp('filename=([^;\\n]+)', caseSensitive: false).firstMatch(raw);
    if (plain != null) {
      final v = plain.group(1)!.replaceAll('"', '').trim();
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  static String _companyMessage(Object e) =>
      e.toString().contains('Company ID não encontrado')
          ? 'Company ID não encontrado.'
          : '';

  static bool _looksLikeImage(PropertyDownloadedFile file) {
    if (file.bytes.length < 32) return false;
    final type = file.mimeType.toLowerCase();
    if (type.contains('json') || type.contains('html')) return false;
    return true;
  }

  /// Tipo pelo cabeçalho; genérico (octet-stream/vazio) → pelos primeiros
  /// bytes (PDF, ZIP, JPEG, PNG, WEBP, GIF).
  static String _mimeOf(String? header, Uint8List bytes) {
    final h = (header ?? '').split(';').first.trim().toLowerCase();
    final generic = h.isEmpty ||
        h == 'application/octet-stream' ||
        h == 'binary/octet-stream';
    if (!generic) return h;
    if (bytes.length >= 4) {
      if (bytes[0] == 0x25 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x44 &&
          bytes[3] == 0x46) {
        return 'application/pdf';
      }
      if (bytes[0] == 0x50 && bytes[1] == 0x4B) return 'application/zip';
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) return 'image/jpeg';
      if (bytes[0] == 0x89 && bytes[1] == 0x50) return 'image/png';
      if (bytes[0] == 0x47 && bytes[1] == 0x49) return 'image/gif';
      if (bytes.length >= 12 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }
    return h.isEmpty ? 'application/octet-stream' : h;
  }
}

// ─── Leitura tolerante ──────────────────────────────────────────────────────

String? _nullIfEmpty(String? v) {
  final t = v?.trim() ?? '';
  return t.isEmpty ? null : t;
}

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// Objeto direto ou envelope `{ data: {...} }`.
Map<String, dynamic>? _unwrap(dynamic raw) {
  final m = _asMap(raw);
  if (m == null) return null;
  final inner = _asMap(m['data']);
  if (inner != null && m['id'] == null) return inner;
  return m;
}

/// Lista direta ou dentro de `data`/`items`/`results`.
List<dynamic> _asList(dynamic raw) {
  if (raw is List) return raw;
  final m = _asMap(raw);
  if (m != null) {
    for (final key in const ['data', 'items', 'results']) {
      final v = m[key];
      if (v is List) return v;
    }
  }
  return const <dynamic>[];
}

String? _text(dynamic v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return t.isEmpty || t == 'null' ? null : t;
}

int _int(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) {
    final t = v.trim();
    return int.tryParse(t) ?? double.tryParse(t)?.toInt() ?? fallback;
  }
  return fallback;
}

double? _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim().replaceAll(',', '.'));
  return null;
}

bool? _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.trim().toLowerCase();
    if (t == 'true' || t == '1') return true;
    if (t == 'false' || t == '0') return false;
  }
  return null;
}

DateTime? _date(dynamic v) {
  final t = _text(v);
  return t == null ? null : DateTime.tryParse(t);
}

dynamic _decode(Uint8List bytes) {
  if (bytes.isEmpty) return null;
  try {
    return jsonDecode(utf8.decode(bytes));
  } catch (_) {
    return null;
  }
}

/// `message` do corpo do Nest (texto ou lista).
String? _messageOf(dynamic body) {
  final m = _asMap(body);
  if (m == null) return null;
  final raw = m['message'];
  if (raw is String && raw.trim().isNotEmpty) return raw.trim();
  if (raw is List && raw.isNotEmpty) return raw.first.toString();
  final err = m['error'];
  if (err is String && err.trim().isNotEmpty && raw == null) return err.trim();
  return null;
}
