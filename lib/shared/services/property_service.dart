import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import '../../core/constants/api_constants.dart';
import '../utils/avatar_url_resolver.dart';

String _readAnyId(
  Map<String, dynamic> map, {
  List<String> preferredKeys = const ['id', '_id'],
}) {
  for (final key in preferredKeys) {
    final raw = map[key];
    final value = raw?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _normalizeMediaUrl(dynamic raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return '';
  if (value.startsWith('data:') || value.startsWith('file:')) return value;
  if (value.startsWith('//')) return 'https:$value';
  return AvatarUrlResolver.resolve(value) ?? '';
}

bool _looksLikePropertyPayload(Map<String, dynamic> map) {
  // Evita escolher envelopes genéricos que possuem `id` mas não os campos
  // da entidade imóvel em si.
  const signalKeys = <String>{
    'title',
    'description',
    'type',
    'status',
    'address',
    'street',
    'city',
    'state',
    'zipCode',
    'zip_code',
    'salePrice',
    'sale_price',
    'rentPrice',
    'rent_price',
    'images',
    'mainImage',
    'main_image',
  };
  for (final key in signalKeys) {
    if (map.containsKey(key)) return true;
  }
  return false;
}

/// Resposta pode ser o próprio objeto da propriedade ou envelope `{ data: { ... } }`.
Map<String, dynamic>? _extractPropertyPayload(Map<String, dynamic>? raw) {
  if (raw == null) return null;

  Map<String, dynamic>? pick(Map<String, dynamic> m) {
    Map<String, dynamic>? fromAnyMap(dynamic v) {
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return null;
    }

    // Prioriza payloads aninhados primeiro (padrão de várias respostas),
    // depois cai para o root somente se ele realmente parecer um imóvel.
    final candidates = <Map<String, dynamic>>[];

    final data = fromAnyMap(m['data']);
    if (data != null) {
      final nestedProperty = fromAnyMap(data['property']);
      if (nestedProperty != null) candidates.add(nestedProperty);
      candidates.add(data);
    }

    final rootProperty = fromAnyMap(m['property']);
    if (rootProperty != null) candidates.add(rootProperty);

    candidates.add(m);

    for (final candidate in candidates) {
      if (_readAnyId(candidate).isEmpty) continue;
      if (_looksLikePropertyPayload(candidate)) return candidate;
    }

    for (final candidate in candidates) {
      if (_readAnyId(candidate).isNotEmpty) {
        return candidate;
      }
    }
    return null;
  }

  return pick(raw);
}

List<NamedEntityOption> parseNamedEntityListFromPage(Map<String, dynamic> root) {
  final raw = root['data'];
  if (raw is! List) return [];
  final out = <NamedEntityOption>[];
  for (final e in raw) {
    if (e is Map<String, dynamic>) {
      final id = e['id']?.toString() ?? '';
      final name = e['name']?.toString() ?? '';
      if (id.isNotEmpty) out.add(NamedEntityOption(id: id, name: name));
    } else if (e is Map) {
      final m = Map<String, dynamic>.from(e);
      final id = m['id']?.toString() ?? '';
      final name = m['name']?.toString() ?? '';
      if (id.isNotEmpty) out.add(NamedEntityOption(id: id, name: name));
    }
  }
  return out;
}

/// Página de resultados de seletor (condomínio / empreendimento) com
/// metadata para paginação no UI.
class NamedEntityPage {
  final List<NamedEntityOption> items;
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  const NamedEntityPage({
    required this.items,
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  bool get hasMore => page < totalPages;

  factory NamedEntityPage.fromJson(Map<String, dynamic> root) {
    final items = parseNamedEntityListFromPage(root);
    int asInt(dynamic v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return NamedEntityPage(
      items: items,
      page: asInt(root['page'], 1),
      limit: asInt(root['limit'], items.length),
      total: asInt(root['total'], items.length),
      totalPages: asInt(root['totalPages'], 1),
    );
  }
}

/// Resposta de `GET /properties/approval-settings/active` — paridade com `imobx-front` / `imobx`.
class PropertyApprovalSettingsActive {
  final bool requireApprovalToBeAvailable;
  final bool requireApprovalToPublishOnSite;
  final bool requireOwnerAuthorizationToBeAvailable;
  final bool preservePublicationOnEdit;
  final bool applyWatermarkToImages;

  /// Sistema de multi-aprovadores ligado: as filas passam a exigir **voto**
  /// em vez do aprovar/recusar direto (mesma bifurcação do web).
  final bool approversEnabled;

  /// Esteira de aprovação de edição de campos protegidos ligada.
  final bool protectedFieldsEnabled;

  const PropertyApprovalSettingsActive({
    this.requireApprovalToBeAvailable = false,
    this.requireApprovalToPublishOnSite = false,
    this.requireOwnerAuthorizationToBeAvailable = false,
    this.preservePublicationOnEdit = true,
    this.applyWatermarkToImages = true,
    this.approversEnabled = false,
    this.protectedFieldsEnabled = false,
  });

  factory PropertyApprovalSettingsActive.fromJson(Map<String, dynamic> json) {
    bool readBool(dynamic v, [bool fallback = false]) {
      if (v is bool) return v;
      if (v is String) return v.toLowerCase() == 'true';
      return fallback;
    }

    return PropertyApprovalSettingsActive(
      requireApprovalToBeAvailable: readBool(
        json['requireApprovalToBeAvailable'] ??
            json['require_approval_to_be_available'],
      ),
      requireApprovalToPublishOnSite: readBool(
        json['requireApprovalToPublishOnSite'] ??
            json['require_approval_to_publish_on_site'],
      ),
      requireOwnerAuthorizationToBeAvailable: readBool(
        json['requireOwnerAuthorizationToBeAvailable'] ??
            json['require_owner_authorization_to_be_available'],
      ),
      preservePublicationOnEdit: readBool(
        json['preservePublicationOnEdit'] ??
            json['preserve_publication_on_edit'],
        true,
      ),
      applyWatermarkToImages: readBool(
        json['applyWatermarkToImages'] ?? json['apply_watermark_to_images'],
        true,
      ),
      approversEnabled: readBool(
        json['approversEnabled'] ?? json['approvers_enabled'],
      ),
      protectedFieldsEnabled: readBool(
        json['protectedFieldsEnabled'] ?? json['protected_fields_enabled'],
      ),
    );
  }
}

/// Opção de equipe em `GET /properties/form-settings`.
class PropertyFormTeamOption {
  final String id;
  final String name;
  final String color;

  const PropertyFormTeamOption({
    required this.id,
    required this.name,
    required this.color,
  });

  factory PropertyFormTeamOption.fromJson(Map<String, dynamic> json) {
    return PropertyFormTeamOption(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '#888888',
    );
  }
}

/// Bundle retornado por `GET /properties/form-settings` (sem `approvalQueueTeamFilter` usado no wizard).
class PropertyFormSettingsBundle {
  final List<String> propertyFormRequiredFields;
  final List<PropertyFormTeamOption> teams;

  const PropertyFormSettingsBundle({
    required this.propertyFormRequiredFields,
    required this.teams,
  });

  factory PropertyFormSettingsBundle.fromJson(Map<String, dynamic> json) {
    final req = json['propertyFormRequiredFields'] ??
        json['property_form_required_fields'];
    final teamsRaw = json['teams'];
    final List<String> requiredList = [];
    if (req is List) {
      for (final x in req) {
        final s = x?.toString().trim() ?? '';
        if (s.isNotEmpty) requiredList.add(s);
      }
    }
    final List<PropertyFormTeamOption> teams = [];
    if (teamsRaw is List) {
      for (final e in teamsRaw) {
        if (e is Map<String, dynamic>) {
          teams.add(PropertyFormTeamOption.fromJson(e));
        } else if (e is Map) {
          teams.add(
            PropertyFormTeamOption.fromJson(
              Map<String, dynamic>.from(e),
            ),
          );
        }
      }
    }
    return PropertyFormSettingsBundle(
      propertyFormRequiredFields: requiredList,
      teams: teams,
    );
  }
}

/// Item mínimo para seletores (condomínio / empreendimento).
class NamedEntityOption {
  final String id;
  final String name;

  const NamedEntityOption({required this.id, required this.name});
}

/// Entidade nomeada com endereço — usada para pré-popular endereço da
/// propriedade quando vinculada a condomínio ou empreendimento (paridade
/// com `condominiumApi.getCondominiumById` / `empreendimentoApi.getEmpreendimentoById`
/// do web).
class NamedEntityWithAddress {
  final String id;
  final String name;
  final String? zipCode;
  final String? street;
  final String? number;
  final String? neighborhood;
  final String? city;
  final String? state;

  const NamedEntityWithAddress({
    required this.id,
    required this.name,
    this.zipCode,
    this.street,
    this.number,
    this.neighborhood,
    this.city,
    this.state,
  });

  factory NamedEntityWithAddress.fromJson(Map<String, dynamic> json) {
    String? str(dynamic v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    return NamedEntityWithAddress(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      zipCode: str(json['zipCode']) ?? str(json['zip_code']),
      street: str(json['street']),
      number: str(json['number']),
      neighborhood: str(json['neighborhood']) ?? str(json['district']),
      city: str(json['city']),
      state: str(json['state']) ?? str(json['uf']),
    );
  }
}

/// Tipos de propriedade — os 16 do back (`imobx/src/entities/property.entity.ts`),
/// na mesma ordem e com os mesmos rótulos de `PropertyTypeOptions` do web
/// (`imobx-front/src/types/property.ts`).
enum PropertyType {
  house('house', 'Casa'),
  townhouse('townhouse', 'Sobrado'),
  apartment('apartment', 'Apartamento'),
  penthouse('penthouse', 'Cobertura'),
  studio('studio', 'Studio'),
  loft('loft', 'Loft'),
  kitnet('kitnet', 'Kitnet'),
  duplex('duplex', 'Duplex'),
  triplex('triplex', 'Triplex'),
  commercial('commercial', 'Comercial'),
  office('office', 'Sala Comercial'),
  store('store', 'Loja'),
  warehouse('warehouse', 'Galpão'),
  farm('farm', 'Fazenda'),
  land('land', 'Terreno'),
  rural('rural', 'Rural');

  final String value;
  final String label;

  const PropertyType(this.value, this.label);

  static PropertyType? fromString(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final e in PropertyType.values) {
      if (e.value == v) return e;
    }
    return null;
  }

  /// Rótulo de um valor cru vindo da API — cai no próprio valor quando o
  /// tipo não é conhecido (mesma regra do `translatePropertyType` do web).
  static String labelOf(String? raw) {
    final t = fromString(raw);
    if (t != null) return t.label;
    return raw?.trim() ?? '';
  }
}

/// Status de propriedade — os 17 do backend (`imobx`), na ordem e com os
/// rótulos de `PropertyStatusOptions` do web.
enum PropertyStatus {
  draft('draft', 'Rascunho'),
  pendingOwnerAuthorization(
    'pending_owner_authorization',
    'Aguardando autorização do proprietário',
  ),
  pendingApproval('pending_approval', 'Aguardando aprovação'),
  pendingPublication(
    'pending_publication',
    'Aguardando publicação no site',
  ),
  available('available', 'Disponível'),
  // Funil de locação (etapas entre Disponível e Locado).
  inService('in_service', 'Em Atendimento'),
  visitScheduled('visit_scheduled', 'Visita Agendada'),
  inVisit('in_visit', 'Em Visita'),
  inNegotiation('in_negotiation', 'Em Negociação'),
  proposalReceived('proposal_received', 'Proposta Recebida'),
  registrationAnalysis('registration_analysis', 'Análise Cadastral'),
  documentation('documentation', 'Documentação'),
  contractDrafting('contract_drafting', 'Contrato em Elaboração'),
  signature('signature', 'Assinatura'),
  rented('rented', 'Alugado'),
  sold('sold', 'Vendido'),
  maintenance('maintenance', 'Manutenção');

  final String value;
  final String label;

  const PropertyStatus(this.value, this.label);

  static PropertyStatus? fromString(String? value) {
    if (value == null) return null;
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final e in PropertyStatus.values) {
      if (e.value == v) return e;
    }
    return null;
  }

  /// Rótulo de um valor cru vindo da API — cai no próprio valor quando o
  /// status não é conhecido (mesma regra do `translatePropertyStatus` do web).
  static String labelOf(String? raw) {
    final s = fromString(raw);
    if (s != null) return s.label;
    return raw?.trim() ?? '';
  }

  /// Etapa do funil de locação (aba "Em negociação" do web).
  bool get isRentalFunnel {
    switch (this) {
      case PropertyStatus.inService:
      case PropertyStatus.visitScheduled:
      case PropertyStatus.inVisit:
      case PropertyStatus.inNegotiation:
      case PropertyStatus.proposalReceived:
      case PropertyStatus.registrationAnalysis:
      case PropertyStatus.documentation:
      case PropertyStatus.contractDrafting:
      case PropertyStatus.signature:
        return true;
      default:
        return false;
    }
  }

  /// Versão compacta do label — útil pra pills de lista em telas pequenas
  /// onde "Aguardando autorização do proprietário" não cabe.
  String get shortLabel {
    switch (this) {
      case PropertyStatus.draft:
        return 'Rascunho';
      case PropertyStatus.pendingApproval:
        return 'Aguardando aprov.';
      case PropertyStatus.pendingOwnerAuthorization:
        return 'Aguard. proprietário';
      case PropertyStatus.pendingPublication:
        return 'Aguard. publicação';
      case PropertyStatus.available:
        return 'Disponível';
      case PropertyStatus.inService:
        return 'Em atendimento';
      case PropertyStatus.visitScheduled:
        return 'Visita agendada';
      case PropertyStatus.inVisit:
        return 'Em visita';
      case PropertyStatus.inNegotiation:
        return 'Em negociação';
      case PropertyStatus.proposalReceived:
        return 'Proposta recebida';
      case PropertyStatus.registrationAnalysis:
        return 'Análise cadastral';
      case PropertyStatus.documentation:
        return 'Documentação';
      case PropertyStatus.contractDrafting:
        return 'Contrato';
      case PropertyStatus.signature:
        return 'Assinatura';
      case PropertyStatus.rented:
        return 'Alugado';
      case PropertyStatus.sold:
        return 'Vendido';
      case PropertyStatus.maintenance:
        return 'Manutenção';
    }
  }
}

/// Motivo da desativação do imóvel — os 9 valores do back
/// (`property-deactivation-reason.enum.ts`), na mesma ordem e com os mesmos
/// rótulos de `PropertyDeactivationReasonLabels` (web e back). O [value] é o
/// que viaja no `reason` do `PATCH /properties/:id/deactivate`.
enum PropertyDeactivationReason {
  rentedByUs('rented_by_us', 'Alugado por esta imobiliária'),
  rentedByOtherAgency(
    'rented_by_other_agency',
    'Alugado por outra imobiliária',
  ),
  soldByUs('sold_by_us', 'Vendido por esta imobiliária'),
  soldByOtherAgency('sold_by_other_agency', 'Vendido por outra imobiliária'),
  ownerWithdrew(
    'owner_withdrew',
    'Proprietário desistiu / retirou o imóvel',
  ),
  duplicateListing('duplicate_listing', 'Cadastro duplicado'),
  incorrectData('incorrect_data', 'Dados incorretos'),
  temporarilyUnavailable(
    'temporarily_unavailable',
    'Indisponível temporariamente',
  ),
  other('other', 'Outro');

  final String value;
  final String label;

  const PropertyDeactivationReason(this.value, this.label);

  static PropertyDeactivationReason? fromString(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return null;
    for (final e in PropertyDeactivationReason.values) {
      if (e.value == v) return e;
    }
    return null;
  }

  /// Rótulo de um valor cru — cai no próprio valor quando o motivo não é
  /// conhecido (a mesma regra do back ao escrever o histórico).
  static String labelOf(String? raw) =>
      fromString(raw)?.label ?? (raw?.trim() ?? '');
}

/// Modelo de Property
class Property {
  final String id;
  final String? code;
  final String title;
  final String description;
  final PropertyType type;
  final PropertyStatus status;

  /// Valor cru de `type` como veio da API. Quando o back devolve um tipo que o
  /// app não conhece, `type` cai no fallback só para a UI, e este campo guarda o
  /// valor real: a edição NUNCA reenvia o fallback no PATCH (paridade de dados).
  final String typeRaw;

  /// Valor cru de `status` como veio da API (mesma regra de [typeRaw]).
  final String statusRaw;
  final String address;
  final String street;
  final String number;
  final String? complement;
  final String city;
  final String state;
  final String zipCode;
  final String neighborhood;
  /// Coordenadas geográficas (mesmos campos `latitude`/`longitude` do web) —
  /// alimentam o mapa da seção Localização. Nulas quando o cadastro não tem
  /// geolocalização.
  final double? latitude;
  final double? longitude;
  final String? internalNotes;
  final String? sector;
  final String? teamId;
  final String? condominiumId;
  final String? empreendimentoId;
  final double totalArea;
  final double? builtArea;
  final int? bedrooms;
  final int? suites;
  final int? bathrooms;
  final int? parkingSpaces;
  final double? salePrice;
  final double? rentPrice;

  /// `'venda'`, `'locacao'` ou `'ambos'` — o recorte declarado do anúncio.
  /// `null` em cadastro anterior à finalidade; nesse caso a regra deriva
  /// dos preços (ver `shared/utils/property_finalidade.dart`).
  final String? finalidade;
  final double? condominiumFee;
  final double? iptu;
  final List<String> features;
  final bool isActive;
  final bool isFeatured;
  final bool? isAvailableForSite;
  final String companyId;
  final String responsibleUserId;
  final List<String>? responsibleUserIds;
  final String? capturedById;
  final List<String>? capturedByIds;
  final PropertyCapturedBy? capturedBy;
  /// Lista completa de captadores (multi) com dados básicos (id/nome/email/phone).
  /// Vem em `/properties/:id` (paridade com o web). Pode coexistir com `capturedBy`
  /// (legacy single). UI deve preferir esta quando presente.
  final List<PropertyCaptor>? captors;
  /// Status da autorização de venda / contrato de agenciamento do proprietário
  /// (ex.: `signed`). Quando assinada, responsável/captador deixam de poder
  /// editar a ficha — apenas gestão (master/admin/manager) e aprovadores.
  final String? ownerAuthStatus;
  /// Data ISO em que a autorização de venda / contrato de agenciamento foi
  /// assinada pelo proprietário. Equivalente a `ownerAuthStatus == 'signed'`
  /// para fins de bloqueio de edição.
  final String? ownerAuthSignedAt;
  /// Data ISO do último envio da autorização para assinatura. Alimenta o
  /// "Enviado em … — aguardando assinatura" da fila do proprietário.
  final String? ownerAuthSentAt;
  /// `true` quando o backend permite reenviar o e-mail do link de assinatura
  /// (documento vivo no Autentique). Espelha `canResendOwnerAuthEmail` do web.
  final bool? canResendOwnerAuthEmail;
  // ─── Fila de aprovação: disponibilidade ───────────────────────────────
  /// Data ISO em que a disponibilidade foi recusada (item ainda na fila
  /// aguardando reenvio para nova análise). Quando preenchida com status
  /// `pending_approval` indica "recusado, aguardando reenvio".
  final String? availabilityRejectedAt;
  /// Motivo livre informado por quem recusou a disponibilidade.
  final String? availabilityRejectionReason;
  /// Data ISO da aprovação da disponibilidade (após a fila).
  final String? availabilityApprovedAt;
  // ─── Fila de aprovação: publicação no site ────────────────────────────
  /// Data ISO em que a publicação no site foi solicitada (entrou na fila).
  final String? publicationRequestedAt;
  /// Data ISO da aprovação da publicação no site.
  final String? publicationApprovedAt;
  /// Data ISO em que a publicação foi recusada (item permanece em
  /// `available` mas com `isAvailableForSite: false`).
  final String? publicationRejectedAt;
  /// Motivo livre informado por quem recusou a publicação.
  final String? publicationRejectionReason;
  /// Indica que o usuário deseja publicar no site mas a empresa exige
  /// aprovação para publicação. Útil para distinguir "rascunho privado"
  /// vs "rascunho com intenção de publicar".
  final bool? sitePublicationApprovalDesired;
  final String createdAt;
  final String updatedAt;
  final int? imageCount;
  final List<PropertyImage>? images;
  final PropertyImage? mainImage;
  final List<PropertyClient>? clients;
  final int? clientCount;
  final PropertyOwner? owner;
  final bool? acceptsNegotiation;
  final double? minSalePrice;
  final double? minRentPrice;
  final String? offerBelowMinSaleAction;
  final String? offerBelowMinRentAction;
  final int? totalOffersCount;
  final int? pendingOffersCount;
  final int? acceptedOffersCount;
  final int? rejectedOffersCount;
  final bool? hasPendingOffers;
  // Campos MCMV
  final bool? mcmvEligible;
  final String? mcmvIncomeRange; // 'faixa1' | 'faixa2' | 'faixa3'
  final double? mcmvMaxValue;
  final double? mcmvSubsidy;
  final List<String>? mcmvDocumentation;
  final String? mcmvNotes;
  // ─── Detalhe: proprietário, responsáveis, desativação e exclusão ──────
  /// Responsáveis pelo imóvel (principal primeiro, depois os adicionais) com
  /// nome/e-mail/telefone — `responsibles` do `GET /properties/:id`. `null`
  /// quando a resposta não traz a lista (listagens).
  final List<PropertyResponsible>? responsibles;

  /// A API deixa o usuário ver os dados do proprietário (gestão ou
  /// responsável pelo imóvel). O web só mostra a seção com `true`; `null`
  /// (campo ausente) conta como "não pode".
  final bool? canViewOwnerData;

  /// Proprietário RESTRITO (responsável = União) e usuário sem acesso: o
  /// bloco `owner` volta vazio de propósito e a ficha mostra "Dados
  /// restritos" em vez de sumir.
  final bool? ownerDataRestricted;

  /// Data ISO da exclusão lógica (soft delete). Imóvel excluído abre só para
  /// consulta (regra do web: nenhuma ação de escrita).
  final String? deletedAt;

  /// Motivo cru da última desativação (um `value` de
  /// [PropertyDeactivationReason]).
  final String? deactivationReason;

  /// Rótulo legível do motivo, como o back devolve.
  final String? deactivationReasonLabel;

  /// Data ISO da última desativação.
  final String? deactivatedAt;

  /// Observação registrada na desativação.
  final String? deactivationNotes;

  // ─── Detalhe (onda 2): vitrine, negociação, vínculos e ficha adicional ─
  /// Terceira chave da vitrine do site (`isSitePremiumLine`, aba "Site").
  /// `null` quando a resposta não trouxe o campo (listagens).
  final bool? isSitePremiumLine;

  /// Nome do condomínio vinculado, como o detalhe devolve — o web usa quando
  /// o cadastro do condomínio não pode ser lido.
  final String? condominiumName;

  /// Nome do empreendimento vinculado (mesma regra de [condominiumName]).
  final String? empreendimentoName;

  /// Aceita permuta: `true`/`false`; `null` = não informado (o bloco
  /// Negociação do web só mostra a linha com valor).
  final bool? acceptsExchange;

  /// Valor máximo aceito em permuta (o "Sim, até …" do web).
  final double? exchangeMaxValue;

  /// Cômodos extras com quantidade (`extraRooms`), na ordem da API.
  final List<PropertyExtraRoom>? extraRooms;

  /// Ficha de venda vinculada (`linkedSaleForm` do detalhe).
  final PropertyLinkedSaleForm? linkedSaleForm;

  /// "Ficha adicional" — campos extras/importados do cadastro (W:393-500).
  final PropertyAdditionalInfo? additionalInfo;

  /// A galeria tem vídeo (`hasVideo`).
  final bool? hasVideo;

  Property({
    required this.id,
    this.code,
    required this.title,
    required this.description,
    required this.type,
    required this.status,
    String? typeRaw,
    String? statusRaw,
    required this.address,
    required this.street,
    required this.number,
    this.complement,
    required this.city,
    required this.state,
    required this.zipCode,
    required this.neighborhood,
    this.latitude,
    this.longitude,
    this.internalNotes,
    this.sector,
    this.teamId,
    this.condominiumId,
    this.empreendimentoId,
    required this.totalArea,
    this.builtArea,
    this.bedrooms,
    this.suites,
    this.bathrooms,
    this.parkingSpaces,
    this.salePrice,
    this.finalidade,
    this.rentPrice,
    this.condominiumFee,
    this.iptu,
    required this.features,
    required this.isActive,
    required this.isFeatured,
    this.isAvailableForSite,
    required this.companyId,
    required this.responsibleUserId,
    this.responsibleUserIds,
    this.capturedById,
    this.capturedByIds,
    this.capturedBy,
    this.captors,
    this.ownerAuthStatus,
    this.ownerAuthSignedAt,
    this.ownerAuthSentAt,
    this.canResendOwnerAuthEmail,
    this.availabilityRejectedAt,
    this.availabilityRejectionReason,
    this.availabilityApprovedAt,
    this.publicationRequestedAt,
    this.publicationApprovedAt,
    this.publicationRejectedAt,
    this.publicationRejectionReason,
    this.sitePublicationApprovalDesired,
    required this.createdAt,
    required this.updatedAt,
    this.imageCount,
    this.images,
    this.mainImage,
    this.clients,
    this.clientCount,
    this.owner,
    this.acceptsNegotiation,
    this.minSalePrice,
    this.minRentPrice,
    this.offerBelowMinSaleAction,
    this.offerBelowMinRentAction,
    this.totalOffersCount,
    this.pendingOffersCount,
    this.acceptedOffersCount,
    this.rejectedOffersCount,
    this.hasPendingOffers,
    this.mcmvEligible,
    this.mcmvIncomeRange,
    this.mcmvMaxValue,
    this.mcmvSubsidy,
    this.mcmvDocumentation,
    this.mcmvNotes,
    this.responsibles,
    this.canViewOwnerData,
    this.ownerDataRestricted,
    this.deletedAt,
    this.deactivationReason,
    this.deactivationReasonLabel,
    this.deactivatedAt,
    this.deactivationNotes,
    this.isSitePremiumLine,
    this.condominiumName,
    this.empreendimentoName,
    this.acceptsExchange,
    this.exchangeMaxValue,
    this.extraRooms,
    this.linkedSaleForm,
    this.additionalInfo,
    this.hasVideo,
  })  : typeRaw = (typeRaw == null || typeRaw.trim().isEmpty)
            ? type.value
            : typeRaw.trim().toLowerCase(),
        statusRaw = (statusRaw == null || statusRaw.trim().isEmpty)
            ? status.value
            : statusRaw.trim().toLowerCase();

  /// `true` quando o tipo cru é um dos 16 conhecidos (o PATCH só envia `type`
  /// nesse caso).
  bool get typeIsKnown => PropertyType.fromString(typeRaw) != null;

  /// `true` quando o status cru é um dos 17 conhecidos.
  bool get statusIsKnown => PropertyStatus.fromString(statusRaw) != null;

  /// Rótulo do tipo — do enum quando conhecido, senão o próprio valor cru.
  String get typeLabel => PropertyType.labelOf(typeRaw);

  /// Rótulo do status — do enum quando conhecido, senão o próprio valor cru.
  String get statusLabel => PropertyStatus.labelOf(statusRaw);

  /// Excluído (soft delete) — a ficha fica só para consulta.
  bool get isDeleted => (deletedAt ?? '').trim().isNotEmpty;

  factory Property.fromJson(Map<String, dynamic> json) {
    // Helper para converter valores que podem vir como String ou num
    double? parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final parsed = double.tryParse(value);
        return parsed;
      }
      return null;
    }

    int? parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value);
        return parsed;
      }
      return null;
    }

    // Coordenada pode vir string com vírgula decimal (dado legado) — o web
    // faz o mesmo replace no `parseLatLng` do PropertyMap.
    double? parseCoord(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        return double.tryParse(value.trim().replaceAll(',', '.'));
      }
      return null;
    }

    // Campos novos lidos com tolerância: bool, "true"/"false" ou 0/1; texto
    // vazio vira null. Tipo inesperado vira null (= comportamento antigo) em
    // vez de derrubar o parse da ficha inteira.
    bool? parseBool(dynamic value) {
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final v = value.trim().toLowerCase();
        if (v == 'true' || v == '1') return true;
        if (v == 'false' || v == '0') return false;
      }
      return null;
    }

    String? parseText(dynamic value) {
      final v = value?.toString().trim() ?? '';
      return v.isEmpty ? null : v;
    }

    return Property(
      id: _readAnyId(
        json,
        preferredKeys: const ['id', '_id', 'propertyId', 'property_id'],
      ),
      code: json['code']?.toString(),
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      // Tipo/status desconhecidos: o enum recebe um fallback só para a UI e o
      // valor real fica em typeRaw/statusRaw (nunca regravado pelo app).
      type: PropertyType.fromString(json['type']?.toString()) ?? PropertyType.house,
      status: PropertyStatus.fromString(json['status']?.toString()) ?? PropertyStatus.draft,
      typeRaw: json['type']?.toString(),
      statusRaw: json['status']?.toString(),
      address: json['address']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      number: json['number']?.toString() ?? '',
      complement: json['complement']?.toString(),
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      zipCode: json['zipCode']?.toString() ?? json['zip_code']?.toString() ?? '',
      neighborhood: json['neighborhood']?.toString() ?? '',
      latitude: parseCoord(json['latitude']),
      longitude: parseCoord(json['longitude']),
      internalNotes: json['internalNotes']?.toString() ??
          json['internal_notes']?.toString(),
      sector: json['sector']?.toString(),
      teamId: json['teamId']?.toString() ?? json['team_id']?.toString(),
      condominiumId:
          json['condominiumId']?.toString() ?? json['condominium_id']?.toString(),
      empreendimentoId: json['empreendimentoId']?.toString() ??
          json['empreendimento_id']?.toString(),
      totalArea: parseDouble(json['totalArea'] ?? json['total_area']) ?? 0.0,
      builtArea: parseDouble(json['builtArea'] ?? json['built_area']),
      bedrooms: parseInt(json['bedrooms']),
      suites: parseInt(json['suites']),
      bathrooms: parseInt(json['bathrooms']),
      parkingSpaces: parseInt(json['parkingSpaces'] ?? json['parking_spaces']),
      salePrice: parseDouble(json['salePrice'] ?? json['sale_price']),
      finalidade: json['finalidade']?.toString(),
      rentPrice: parseDouble(json['rentPrice'] ?? json['rent_price']),
      condominiumFee: parseDouble(json['condominiumFee'] ?? json['condominium_fee']),
      iptu: parseDouble(json['iptu']),
      features: json['features'] != null
          ? List<String>.from((json['features'] as List).map((e) => e.toString()))
          : [],
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? false,
      isFeatured: json['isFeatured'] as bool? ?? json['is_featured'] as bool? ?? false,
      isAvailableForSite: json['isAvailableForSite'] as bool? ?? json['is_available_for_site'] as bool?,
      companyId: json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      responsibleUserId: json['responsibleUserId']?.toString() ?? json['responsible_user_id']?.toString() ?? '',
      responsibleUserIds: () {
        final raw = json['responsibleUserIds'] ?? json['responsible_user_ids'];
        if (raw is List) {
          return raw
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return null;
      }(),
      capturedById: json['capturedById']?.toString() ?? json['captured_by_id']?.toString(),
      capturedByIds: () {
        final raw = json['capturedByIds'] ?? json['captured_by_ids'];
        if (raw is List) {
          return raw
              .map((e) => e?.toString() ?? '')
              .where((e) => e.isNotEmpty)
              .toList();
        }
        return null;
      }(),
      ownerAuthStatus: json['ownerAuthStatus']?.toString() ??
          json['owner_auth_status']?.toString(),
      ownerAuthSignedAt: json['ownerAuthSignedAt']?.toString() ??
          json['owner_auth_signed_at']?.toString(),
      ownerAuthSentAt: json['ownerAuthSentAt']?.toString() ??
          json['owner_auth_sent_at']?.toString(),
      canResendOwnerAuthEmail: json['canResendOwnerAuthEmail'] as bool? ??
          json['can_resend_owner_auth_email'] as bool?,
      availabilityRejectedAt: json['availabilityRejectedAt']?.toString() ??
          json['availability_rejected_at']?.toString(),
      availabilityRejectionReason: json['availabilityRejectionReason']
              ?.toString() ??
          json['availability_rejection_reason']?.toString(),
      availabilityApprovedAt: json['availabilityApprovedAt']?.toString() ??
          json['availability_approved_at']?.toString(),
      publicationRequestedAt: json['publicationRequestedAt']?.toString() ??
          json['publication_requested_at']?.toString(),
      publicationApprovedAt: json['publicationApprovedAt']?.toString() ??
          json['publication_approved_at']?.toString(),
      publicationRejectedAt: json['publicationRejectedAt']?.toString() ??
          json['publication_rejected_at']?.toString(),
      publicationRejectionReason: json['publicationRejectionReason']
              ?.toString() ??
          json['publication_rejection_reason']?.toString(),
      sitePublicationApprovalDesired:
          json['sitePublicationApprovalDesired'] as bool? ??
              json['site_publication_approval_desired'] as bool?,
      captors: () {
        final raw = json['captors'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) =>
                  PropertyCaptor.fromJson(Map<String, dynamic>.from(e)))
              .where((c) => c.id.isNotEmpty)
              .toList();
        }
        return null;
      }(),
      capturedBy: json['capturedBy'] != null
          ? PropertyCapturedBy.fromJson(json['capturedBy'] as Map<String, dynamic>)
          : json['captured_by'] != null
              ? PropertyCapturedBy.fromJson(json['captured_by'] as Map<String, dynamic>)
              : null,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt: json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
      imageCount: parseInt(json['imageCount'] ?? json['image_count']),
      images: json['images'] != null
          ? (json['images'] as List).map((e) => PropertyImage.fromJson(e as Map<String, dynamic>)).toList()
          : null,
      mainImage: json['mainImage'] != null
          ? PropertyImage.fromJson(json['mainImage'] as Map<String, dynamic>)
          : json['main_image'] != null
              ? PropertyImage.fromJson(json['main_image'] as Map<String, dynamic>)
              : null,
      clients: json['clients'] != null
          ? (json['clients'] as List).map((e) => PropertyClient.fromJson(e as Map<String, dynamic>)).toList()
          : null,
      clientCount: parseInt(json['clientCount'] ?? json['client_count']),
      owner: json['owner'] != null
          ? PropertyOwner.fromJson(json['owner'] as Map<String, dynamic>)
          : null,
      acceptsNegotiation: json['acceptsNegotiation'] as bool? ?? json['accepts_negotiation'] as bool?,
      minSalePrice: parseDouble(json['minSalePrice'] ?? json['min_sale_price']),
      minRentPrice: parseDouble(json['minRentPrice'] ?? json['min_rent_price']),
      offerBelowMinSaleAction: json['offerBelowMinSaleAction']?.toString() ?? json['offer_below_min_sale_action']?.toString(),
      offerBelowMinRentAction: json['offerBelowMinRentAction']?.toString() ?? json['offer_below_min_rent_action']?.toString(),
      totalOffersCount: parseInt(json['totalOffersCount'] ?? json['total_offers_count']),
      pendingOffersCount: parseInt(json['pendingOffersCount'] ?? json['pending_offers_count']),
      acceptedOffersCount: parseInt(json['acceptedOffersCount'] ?? json['accepted_offers_count']),
      rejectedOffersCount: parseInt(json['rejectedOffersCount'] ?? json['rejected_offers_count']),
      hasPendingOffers: json['hasPendingOffers'] as bool? ?? json['has_pending_offers'] as bool?,
      mcmvEligible: json['mcmvEligible'] as bool? ?? json['mcmv_eligible'] as bool?,
      mcmvIncomeRange: json['mcmvIncomeRange']?.toString() ?? json['mcmv_income_range']?.toString(),
      mcmvMaxValue: parseDouble(json['mcmvMaxValue'] ?? json['mcmv_max_value']),
      mcmvSubsidy: parseDouble(json['mcmvSubsidy'] ?? json['mcmv_subsidy']),
      mcmvDocumentation: json['mcmvDocumentation'] != null
          ? List<String>.from((json['mcmvDocumentation'] as List).map((e) => e.toString()))
          : json['mcmv_documentation'] != null
              ? List<String>.from((json['mcmv_documentation'] as List).map((e) => e.toString()))
              : null,
      mcmvNotes: json['mcmvNotes']?.toString() ?? json['mcmv_notes']?.toString(),
      responsibles: () {
        final raw = json['responsibles'];
        if (raw is! List) return null;
        return raw
            .whereType<Map>()
            .map((e) =>
                PropertyResponsible.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }(),
      canViewOwnerData:
          parseBool(json['canViewOwnerData'] ?? json['can_view_owner_data']),
      ownerDataRestricted: parseBool(
        json['ownerDataRestricted'] ?? json['owner_data_restricted'],
      ),
      deletedAt: parseText(json['deletedAt'] ?? json['deleted_at']),
      deactivationReason:
          parseText(json['deactivationReason'] ?? json['deactivation_reason']),
      deactivationReasonLabel: parseText(
        json['deactivationReasonLabel'] ?? json['deactivation_reason_label'],
      ),
      deactivatedAt:
          parseText(json['deactivatedAt'] ?? json['deactivated_at']),
      deactivationNotes:
          parseText(json['deactivationNotes'] ?? json['deactivation_notes']),
      isSitePremiumLine: parseBool(
        json['isSitePremiumLine'] ?? json['is_site_premium_line'],
      ),
      condominiumName:
          parseText(json['condominiumName'] ?? json['condominium_name']),
      empreendimentoName: parseText(
        json['empreendimentoName'] ?? json['empreendimento_name'],
      ),
      acceptsExchange:
          parseBool(json['acceptsExchange'] ?? json['accepts_exchange']),
      exchangeMaxValue:
          parseDouble(json['exchangeMaxValue'] ?? json['exchange_max_value']),
      extraRooms: PropertyExtraRoom.listFrom(
        json['extraRooms'] ?? json['extra_rooms'],
      ),
      linkedSaleForm: PropertyLinkedSaleForm.tryParse(
        json['linkedSaleForm'] ?? json['linked_sale_form'],
      ),
      additionalInfo: PropertyAdditionalInfo.fromJson(json),
      hasVideo: parseBool(json['hasVideo'] ?? json['has_video']),
    );
  }
}

class PropertyCapturedBy {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;

  PropertyCapturedBy({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
  });

  factory PropertyCapturedBy.fromJson(Map<String, dynamic> json) {
    return PropertyCapturedBy(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      avatar: AvatarUrlResolver.resolve(json['avatar']?.toString()),
    );
  }
}

/// Captador (multi). O backend devolve `captors` em /properties/:id com
/// `{ id, name?, email?, phone? }`. O `avatar` é opcional e quase nunca vem,
/// então a UI cai pro fallback de iniciais.
class PropertyCaptor {
  final String id;
  final String? name;
  final String? email;
  final String? phone;
  final String? avatar;

  PropertyCaptor({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.avatar,
  });

  factory PropertyCaptor.fromJson(Map<String, dynamic> json) {
    return PropertyCaptor(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      avatar: AvatarUrlResolver.resolve(json['avatar']?.toString()),
    );
  }
}

/// Responsável pelo imóvel (principal ou adicional) — item de
/// `responsibles` em `/properties/:id`: `{ id, name?, email?, phone? }`, com
/// o principal primeiro. `avatar` quase nunca vem; a UI cai nas iniciais.
class PropertyResponsible {
  final String id;
  final String? name;
  final String? email;
  final String? phone;
  final String? avatar;

  const PropertyResponsible({
    required this.id,
    this.name,
    this.email,
    this.phone,
    this.avatar,
  });

  factory PropertyResponsible.fromJson(Map<String, dynamic> json) {
    String? text(dynamic value) {
      final v = value?.toString().trim() ?? '';
      return v.isEmpty ? null : v;
    }

    return PropertyResponsible(
      id: text(json['id']) ?? text(json['userId']) ?? '',
      name: text(json['name']),
      email: text(json['email']),
      phone: text(json['phone']),
      avatar: AvatarUrlResolver.resolve(text(json['avatar'])),
    );
  }
}

class PropertyImage {
  final String id;
  final String url;
  final String? thumbnailUrl;
  final String category;
  final bool isMain;
  final String createdAt;

  /// `image` ou `video` (`mediaType` da galeria). Cadastro antigo sem o
  /// campo conta como foto — a mesma leitura do back.
  final String mediaType;

  /// Duração do vídeo em segundos (até 1:40), quando informada.
  final int? durationSeconds;

  /// Aparece no site público (`showOnPublicSite`); `null` = não informado.
  final bool? showOnPublicSite;

  PropertyImage({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.category,
    required this.isMain,
    required this.createdAt,
    this.mediaType = 'image',
    this.durationSeconds,
    this.showOnPublicSite,
  });

  /// Item de mídia é vídeo — toca, não vira `<img>` (paridade
  /// `isVideoMedia` do carrossel web).
  bool get isVideo => mediaType.trim().toLowerCase() == 'video';

  /// Capa do vídeo (quadro gerado no upload) — só quando é diferente do
  /// próprio arquivo, a mesma regra do `videoPosterUrl` do web. Para foto,
  /// `null`.
  String? get posterUrl {
    if (!isVideo) return null;
    final thumb = thumbnailUrl?.trim() ?? '';
    if (thumb.isEmpty || thumb == url) return null;
    return thumb;
  }

  /// Cópia com campos trocados — preserva o tipo de mídia (reconstruir com
  /// o construtor sem `mediaType` transformaria vídeo em foto).
  PropertyImage copyWith({
    String? url,
    String? thumbnailUrl,
    String? category,
    bool? isMain,
  }) {
    return PropertyImage(
      id: id,
      url: url ?? this.url,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      category: category ?? this.category,
      isMain: isMain ?? this.isMain,
      createdAt: createdAt,
      mediaType: mediaType,
      durationSeconds: durationSeconds,
      showOnPublicSite: showOnPublicSite,
    );
  }

  factory PropertyImage.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['url'] ??
        json['imageUrl'] ??
        json['image_url'] ??
        json['src'] ??
        json['path'];
    return PropertyImage(
      id: _readAnyId(
        json,
        preferredKeys: const ['id', '_id', 'imageId', 'image_id'],
      ),
      url: _normalizeMediaUrl(rawUrl),
      thumbnailUrl: _normalizeMediaUrl(
        json['thumbnailUrl'] ??
            json['thumbnail_url'] ??
            json['thumbUrl'] ??
            json['thumb_url'],
      ),
      category: json['category']?.toString() ?? 'general',
      isMain: json['isMain'] as bool? ?? json['is_main'] as bool? ?? false,
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      mediaType: _optText(json['mediaType'] ?? json['media_type'])
              ?.toLowerCase() ??
          'image',
      durationSeconds:
          _optNum(json['durationSeconds'] ?? json['duration_seconds'])
              ?.round(),
      showOnPublicSite:
          _optBool(json['showOnPublicSite'] ?? json['show_on_public_site']),
    );
  }
}

class PropertyClient {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String type;
  final String status;
  final String interestType;
  final String? notes;
  final String? contactedAt;
  final String createdAt;
  final String responsibleUserName;

  PropertyClient({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.type,
    required this.status,
    required this.interestType,
    this.notes,
    this.contactedAt,
    required this.createdAt,
    required this.responsibleUserName,
  });

  factory PropertyClient.fromJson(Map<String, dynamic> json) {
    return PropertyClient(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      interestType: json['interestType']?.toString() ?? json['interest_type']?.toString() ?? '',
      notes: json['notes']?.toString(),
      contactedAt: json['contactedAt']?.toString() ?? json['contacted_at']?.toString(),
      createdAt: json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      responsibleUserName: json['responsibleUserName']?.toString() ?? json['responsible_user_name']?.toString() ?? '',
    );
  }
}

class PropertyOwner {
  final String? name;
  final String? email;
  final String? phone;
  final String? document;
  final String? address;

  PropertyOwner({
    this.name,
    this.email,
    this.phone,
    this.document,
    this.address,
  });

  factory PropertyOwner.fromJson(Map<String, dynamic> json) {
    return PropertyOwner(
      name: json['name']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      document: json['document']?.toString(),
      address: json['address']?.toString(),
    );
  }
}

// ─── Detalhe (onda 2): leitura tolerante ──────────────────────────────────

String? _optText(dynamic value) {
  if (value == null) return null;
  final v = value.toString().trim();
  return v.isEmpty || v == 'null' ? null : v;
}

bool? _optBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final v = value.trim().toLowerCase();
    if (v == 'true' || v == '1') return true;
    if (v == 'false' || v == '0') return false;
  }
  return null;
}

num? _optNum(dynamic value) {
  if (value is num) return value;
  if (value is String) {
    final v = value.trim().replaceAll(',', '.');
    if (v.isEmpty) return null;
    return num.tryParse(v);
  }
  return null;
}

/// Cômodo extra do cadastro (`extraRooms`: `{ name, quantity }`).
class PropertyExtraRoom {
  final String name;
  final int quantity;

  const PropertyExtraRoom({required this.name, required this.quantity});

  /// Lista da API — ignora item sem nome ou com quantidade ≤ 0 (a mesma
  /// regra de exibição do web). `null` quando o campo não veio.
  static List<PropertyExtraRoom>? listFrom(dynamic raw) {
    if (raw is! List) return null;
    final out = <PropertyExtraRoom>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final name = _optText(item['name']);
      final quantity = _optNum(item['quantity'])?.round() ?? 0;
      if (name == null || quantity <= 0) continue;
      out.add(PropertyExtraRoom(name: name, quantity: quantity));
    }
    return out;
  }
}

/// Pessoa envolvida na ficha de venda vinculada — `role` cru da API
/// (`criador`, `membro_vinculado`, `signatário (pending)`…).
class PropertyLinkedSaleFormParticipant {
  final String role;
  final String name;
  final String? email;

  const PropertyLinkedSaleFormParticipant({
    required this.role,
    required this.name,
    this.email,
  });
}

/// Ficha de venda vinculada ao imóvel (`linkedSaleForm` do detalhe —
/// `PropertyLinkedSaleFormDetailDto` do back).
class PropertyLinkedSaleForm {
  final String id;
  final String formNumber;

  /// `waiting_for_signature`, `processing`, `finalized`, `canceled`.
  final String status;

  /// Ficha finalizada — pode haver PDF assinado na Autentique.
  final bool canDownloadSignedPdf;
  final List<PropertyLinkedSaleFormParticipant> participants;

  const PropertyLinkedSaleForm({
    required this.id,
    required this.formNumber,
    required this.status,
    required this.canDownloadSignedPdf,
    this.participants = const <PropertyLinkedSaleFormParticipant>[],
  });

  /// `null` quando o campo não veio ou veio sem id.
  static PropertyLinkedSaleForm? tryParse(dynamic raw) {
    if (raw is! Map) return null;
    final id = _optText(raw['id']);
    if (id == null) return null;
    final people = <PropertyLinkedSaleFormParticipant>[];
    final list = raw['participants'];
    if (list is List) {
      for (final p in list) {
        if (p is! Map) continue;
        final name = _optText(p['name']);
        if (name == null) continue;
        people.add(
          PropertyLinkedSaleFormParticipant(
            role: _optText(p['role']) ?? '',
            name: name,
            email: _optText(p['email']),
          ),
        );
      }
    }
    return PropertyLinkedSaleForm(
      id: id,
      formNumber: _optText(raw['formNumber']) ?? '',
      status: _optText(raw['status']) ?? '',
      canDownloadSignedPdf: _optBool(raw['canDownloadSignedPdf']) ?? false,
      participants: people,
    );
  }
}

/// "Ficha adicional" do detalhe — campos extras do cadastro (migração/CRM)
/// que o web lista em `propertyExtendedImportRows` (W:393-500). Tudo
/// opcional; texto vazio vira `null`. As datas e motivos da fila de
/// aprovação (publicação/disponibilidade) já moram em [Property].
class PropertyAdditionalInfo {
  final String? ownerId;
  final String? lastUpdateEntryAt;
  final String? soldAt;
  final String? rentedAt;
  final bool? isHighStandard;
  final bool? hasPlaque;
  final bool? hasExclusivity;
  final bool? isPrivate;
  final num? builtYear;
  final String? alternativeCode;
  final num? unitFloor;
  final num? floors;
  final num? buildings;
  final num? elevators;
  final String? sunPosition;
  final String? propertySituation;
  final num? lotArea;
  final String? lotMeasureType;
  final String? propertyUnity;
  final String? visitTime;
  final String? siteContact;
  final String? houseRules;
  final String? nearby;
  final bool? bail;
  final bool? suretyBond;
  final bool? bondApplication;
  final bool? credpagoGuarantee;
  final bool? guarantor;
  final num? ownersPercentage;
  final num? ownersRate;
  final String? siteMetaDescription;

  const PropertyAdditionalInfo({
    this.ownerId,
    this.lastUpdateEntryAt,
    this.soldAt,
    this.rentedAt,
    this.isHighStandard,
    this.hasPlaque,
    this.hasExclusivity,
    this.isPrivate,
    this.builtYear,
    this.alternativeCode,
    this.unitFloor,
    this.floors,
    this.buildings,
    this.elevators,
    this.sunPosition,
    this.propertySituation,
    this.lotArea,
    this.lotMeasureType,
    this.propertyUnity,
    this.visitTime,
    this.siteContact,
    this.houseRules,
    this.nearby,
    this.bail,
    this.suretyBond,
    this.bondApplication,
    this.credpagoGuarantee,
    this.guarantor,
    this.ownersPercentage,
    this.ownersRate,
    this.siteMetaDescription,
  });

  /// Lê direto do JSON do imóvel (os campos ficam na raiz do detalhe).
  factory PropertyAdditionalInfo.fromJson(Map<String, dynamic> json) {
    dynamic pick(String camel, String snake) => json[camel] ?? json[snake];
    return PropertyAdditionalInfo(
      ownerId: _optText(pick('ownerId', 'owner_id')),
      lastUpdateEntryAt:
          _optText(pick('lastUpdateEntryAt', 'last_update_entry_at')),
      soldAt: _optText(pick('soldAt', 'sold_at')),
      rentedAt: _optText(pick('rentedAt', 'rented_at')),
      isHighStandard: _optBool(pick('isHighStandard', 'is_high_standard')),
      hasPlaque: _optBool(pick('hasPlaque', 'has_plaque')),
      hasExclusivity: _optBool(pick('hasExclusivity', 'has_exclusivity')),
      isPrivate: _optBool(pick('isPrivate', 'is_private')),
      builtYear: _optNum(pick('builtYear', 'built_year')),
      alternativeCode: _optText(pick('alternativeCode', 'alternative_code')),
      unitFloor: _optNum(pick('unitFloor', 'unit_floor')),
      floors: _optNum(json['floors']),
      buildings: _optNum(json['buildings']),
      elevators: _optNum(json['elevators']),
      sunPosition: _optText(pick('sunPosition', 'sun_position')),
      propertySituation:
          _optText(pick('propertySituation', 'property_situation')),
      lotArea: _optNum(pick('lotArea', 'lot_area')),
      lotMeasureType: _optText(pick('lotMeasureType', 'lot_measure_type')),
      propertyUnity: _optText(pick('propertyUnity', 'property_unity')),
      visitTime: _optText(pick('visitTime', 'visit_time')),
      siteContact: _optText(pick('siteContact', 'site_contact')),
      houseRules: _optText(pick('houseRules', 'house_rules')),
      nearby: _optText(json['nearby']),
      bail: _optBool(json['bail']),
      suretyBond: _optBool(pick('suretyBond', 'surety_bond')),
      bondApplication: _optBool(pick('bondApplication', 'bond_application')),
      credpagoGuarantee:
          _optBool(pick('credpagoGuarantee', 'credpago_guarantee')),
      guarantor: _optBool(json['guarantor']),
      ownersPercentage: _optNum(pick('ownersPercentage', 'owners_percentage')),
      ownersRate: _optNum(pick('ownersRate', 'owners_rate')),
      siteMetaDescription:
          _optText(pick('siteMetaDescription', 'site_meta_description')),
    );
  }
}

/// Resposta de listagem de propriedades
class PropertiesListResponse {
  final List<Property> data;
  final int total;
  final int page;
  final int limit;
  final int totalPages;

  PropertiesListResponse({
    required this.data,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
  });

  factory PropertiesListResponse.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v, int fallback) {
      if (v == null) return fallback;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    final dataList = json['data'] as List<dynamic>? ?? [];
    return PropertiesListResponse(
      data: dataList.map((e) => Property.fromJson(e as Map<String, dynamic>)).toList(),
      total: asInt(json['total'], 0),
      page: asInt(json['page'], 1),
      limit: asInt(json['limit'], 50),
      totalPages: asInt(
        json['totalPages'] ?? json['total_pages'],
        1,
      ),
    );
  }
}

/// Tipo de sugestão de localização (espelha o web).
enum PropertyLocationSuggestionKind {
  condominium,
  street,
  neighborhood,
  empreendimento,
  generic;

  static PropertyLocationSuggestionKind fromString(String? value) {
    switch (value) {
      case 'condominium':
        return PropertyLocationSuggestionKind.condominium;
      case 'street':
        return PropertyLocationSuggestionKind.street;
      case 'neighborhood':
        return PropertyLocationSuggestionKind.neighborhood;
      case 'empreendimento':
        return PropertyLocationSuggestionKind.empreendimento;
      default:
        return PropertyLocationSuggestionKind.generic;
    }
  }
}

/// Sugestão de localização retornada pelo backend para o autocomplete.
class PropertyLocationSuggestion {
  final PropertyLocationSuggestionKind kind;
  final String label;
  final String? subtitle;
  final String? condominiumId;
  final String? street;
  final String? neighborhood;
  final String? empreendimentoId;

  const PropertyLocationSuggestion({
    required this.kind,
    required this.label,
    this.subtitle,
    this.condominiumId,
    this.street,
    this.neighborhood,
    this.empreendimentoId,
  });

  factory PropertyLocationSuggestion.fromJson(Map<String, dynamic> json) {
    return PropertyLocationSuggestion(
      kind: PropertyLocationSuggestionKind.fromString(
        json['kind']?.toString(),
      ),
      label: json['label']?.toString() ?? '',
      subtitle: json['subtitle']?.toString(),
      condominiumId: json['condominiumId']?.toString(),
      street: json['street']?.toString(),
      neighborhood: json['neighborhood']?.toString(),
      empreendimentoId: json['empreendimentoId']?.toString(),
    );
  }
}

/// Filtros de propriedades
/// Escopo "carteira" do corretor — paridade com web `portfolioScope`.
/// O backend aceita este parâmetro para filtrar imóveis por uma combinação
/// pré-definida de status/flags (ex.: pendentes inclui `pending_approval` e
/// `pending_owner_authorization`).
enum PortfolioScope {
  available('available'),
  pending('pending'),
  rejected('rejected'),
  sold('sold');

  final String value;
  const PortfolioScope(this.value);
}

class PropertyFilters {
  final PropertyType? type;
  final PropertyStatus? status;
  final String? city;
  final String? state;
  final String? neighborhood;
  final double? minPrice;
  final double? maxPrice;
  final double? minArea;
  final double? maxArea;
  final int? bedrooms;
  final int? bathrooms;
  final int? parkingSpaces;
  final List<String>? features;
  final bool? isActive;
  final bool? isFeatured;
  final String? companyId;
  final String? responsibleUserId;
  final String? search;
  final bool? onlyMyData;
  final PortfolioScope? portfolioScope;
  final bool? includeInactive;

  PropertyFilters({
    this.type,
    this.status,
    this.city,
    this.state,
    this.neighborhood,
    this.minPrice,
    this.maxPrice,
    this.minArea,
    this.maxArea,
    this.bedrooms,
    this.bathrooms,
    this.parkingSpaces,
    this.features,
    this.isActive,
    this.isFeatured,
    this.companyId,
    this.responsibleUserId,
    this.search,
    this.onlyMyData,
    this.portfolioScope,
    this.includeInactive,
  });

  Map<String, dynamic> toQueryParams() {
    final params = <String, dynamic>{};
    if (type != null) params['type'] = type!.value;
    if (status != null) params['status'] = status!.value;
    if (city != null) params['city'] = city;
    if (state != null) params['state'] = state;
    if (neighborhood != null) params['neighborhood'] = neighborhood;
    if (minPrice != null) params['minPrice'] = minPrice;
    if (maxPrice != null) params['maxPrice'] = maxPrice;
    if (minArea != null) params['minArea'] = minArea;
    if (maxArea != null) params['maxArea'] = maxArea;
    if (bedrooms != null) params['bedrooms'] = bedrooms;
    if (bathrooms != null) params['bathrooms'] = bathrooms;
    if (parkingSpaces != null) params['parkingSpaces'] = parkingSpaces;
    if (features != null && features!.isNotEmpty) params['features'] = features;
    if (isActive != null) params['isActive'] = isActive;
    if (isFeatured != null) params['isFeatured'] = isFeatured;
    if (companyId != null) params['companyId'] = companyId;
    if (responsibleUserId != null) params['responsibleUserId'] = responsibleUserId;
    if (search != null && search!.isNotEmpty) params['search'] = search;
    if (onlyMyData != null) params['onlyMyData'] = onlyMyData;
    if (portfolioScope != null) {
      params['portfolioScope'] = portfolioScope!.value;
    }
    if (includeInactive != null) params['includeInactive'] = includeInactive;
    return params;
  }

  PropertyFilters copyWith({
    PropertyType? type,
    PropertyStatus? status,
    String? city,
    String? state,
    String? neighborhood,
    double? minPrice,
    double? maxPrice,
    double? minArea,
    double? maxArea,
    int? bedrooms,
    int? bathrooms,
    int? parkingSpaces,
    List<String>? features,
    bool? isActive,
    bool? isFeatured,
    String? companyId,
    String? responsibleUserId,
    String? search,
    bool? onlyMyData,
    PortfolioScope? portfolioScope,
    bool? includeInactive,
  }) {
    return PropertyFilters(
      type: type ?? this.type,
      status: status ?? this.status,
      city: city ?? this.city,
      state: state ?? this.state,
      neighborhood: neighborhood ?? this.neighborhood,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
      minArea: minArea ?? this.minArea,
      maxArea: maxArea ?? this.maxArea,
      bedrooms: bedrooms ?? this.bedrooms,
      bathrooms: bathrooms ?? this.bathrooms,
      parkingSpaces: parkingSpaces ?? this.parkingSpaces,
      features: features ?? this.features,
      isActive: isActive ?? this.isActive,
      isFeatured: isFeatured ?? this.isFeatured,
      companyId: companyId ?? this.companyId,
      responsibleUserId: responsibleUserId ?? this.responsibleUserId,
      search: search ?? this.search,
      onlyMyData: onlyMyData ?? this.onlyMyData,
      portfolioScope: portfolioScope ?? this.portfolioScope,
      includeInactive: includeInactive ?? this.includeInactive,
    );
  }

  /// Versão que aceita `null` explícito para resetar campos
  /// (necessário pra "Todos" — limpar portfolioScope sem perder o resto).
  PropertyFilters copyWithNullable({
    PortfolioScope? portfolioScope,
    bool? includeInactive,
    bool resetPortfolioScope = false,
    bool resetIncludeInactive = false,
    String? responsibleUserId,
    bool resetResponsibleUserId = false,
    bool? onlyMyData,
    bool resetOnlyMyData = false,
    bool? isActive,
    bool resetIsActive = false,
  }) {
    return PropertyFilters(
      type: type,
      status: status,
      city: city,
      state: state,
      neighborhood: neighborhood,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minArea: minArea,
      maxArea: maxArea,
      bedrooms: bedrooms,
      bathrooms: bathrooms,
      parkingSpaces: parkingSpaces,
      features: features,
      isActive: resetIsActive ? null : (isActive ?? this.isActive),
      isFeatured: isFeatured,
      companyId: companyId,
      responsibleUserId: resetResponsibleUserId
          ? null
          : (responsibleUserId ?? this.responsibleUserId),
      search: search,
      onlyMyData: resetOnlyMyData ? null : (onlyMyData ?? this.onlyMyData),
      portfolioScope: resetPortfolioScope
          ? null
          : (portfolioScope ?? this.portfolioScope),
      includeInactive: resetIncludeInactive
          ? null
          : (includeInactive ?? this.includeInactive),
    );
  }
}

/// Imóvel que coincide com o endereço de um cadastro novo — espelho de
/// `PropertyDuplicateCandidate` do back (`POST /properties/duplicate-check` e
/// corpo do 409 `PROPERTY_DUPLICATE_DETECTED`).
class PropertyDuplicateCandidate {
  final String id;
  final String? code;
  final String title;
  final String street;
  final String number;
  final String neighborhood;
  final String city;
  final String state;
  final String? propertyUnity;
  final String? complement;

  const PropertyDuplicateCandidate({
    required this.id,
    this.code,
    required this.title,
    required this.street,
    required this.number,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.propertyUnity,
    this.complement,
  });

  factory PropertyDuplicateCandidate.fromJson(Map<String, dynamic> json) {
    String? opt(dynamic v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? null : s;
    }

    return PropertyDuplicateCandidate(
      id: _readAnyId(json),
      code: opt(json['code']),
      title: json['title']?.toString().trim() ?? '',
      street: json['street']?.toString().trim() ?? '',
      number: json['number']?.toString().trim() ?? '',
      neighborhood: json['neighborhood']?.toString().trim() ?? '',
      city: json['city']?.toString().trim() ?? '',
      state: json['state']?.toString().trim() ?? '',
      propertyUnity: opt(json['propertyUnity']),
      complement: opt(json['complement']),
    );
  }

  /// Lista vinda da API (`duplicates`), ignorando itens sem id.
  static List<PropertyDuplicateCandidate> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PropertyDuplicateCandidate>[];
    for (final item in raw) {
      if (item is Map) {
        final c = PropertyDuplicateCandidate.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (c.id.isNotEmpty) out.add(c);
      }
    }
    return out;
  }
}

/// Resposta de `POST /properties/duplicate-check`.
class PropertyDuplicateCheckResult {
  final bool hasDuplicate;
  final List<PropertyDuplicateCandidate> duplicates;

  const PropertyDuplicateCheckResult({
    required this.hasDuplicate,
    required this.duplicates,
  });
}

/// Serviço de Propriedades
class PropertyService {
  PropertyService._();

  static final PropertyService instance = PropertyService._();
  final ApiService _apiService = ApiService.instance;

  /// Lista propriedades com filtros e paginação
  Future<ApiResponse<PropertiesListResponse>> getProperties({
    int page = 1,
    int limit = 50,
    PropertyFilters? filters,
  }) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Listando propriedades');
    debugPrint('   - page: $page');
    debugPrint('   - limit: $limit');

    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
        // Paridade web (`getCombinedFilters`): sempre envia
        // includeLastActivity=true para trazer o último evento por imóvel.
        'includeLastActivity': 'true',
      };

      if (filters != null) {
        queryParams.addAll(filters.toQueryParams());
      }
      debugPrint('   - filters: $queryParams');

      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.success && response.data != null) {
        try {
          final listResponse = PropertiesListResponse.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] ${listResponse.data.length} propriedades encontradas');
          return ApiResponse.success(
            data: listResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar propriedades',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Configuração de aprovação/publicação (qualquer usuário com `property:view`).
  Future<ApiResponse<PropertyApprovalSettingsActive>>
      getPropertyApprovalSettingsActive() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/approval-settings/active',
      );
      if (response.success && response.data != null) {
        final root = response.data!;
        final map = root['data'] is Map<String, dynamic>
            ? root['data'] as Map<String, dynamic>
            : root;
        return ApiResponse.success(
          data: PropertyApprovalSettingsActive.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao carregar configuração de aprovação',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] approval-settings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `GET /properties/form-settings` — equipes e campos obrigatórios (mesma regra do web).
  Future<ApiResponse<PropertyFormSettingsBundle>> getPropertyFormSettings() async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/form-settings',
      );
      if (response.success && response.data != null) {
        final root = response.data!;
        final map = root['data'] is Map<String, dynamic>
            ? root['data'] as Map<String, dynamic>
            : root;
        return ApiResponse.success(
          data: PropertyFormSettingsBundle.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message:
            response.message ?? 'Erro ao carregar configuração do formulário',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] form-settings: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista mínima para o seletor do wizard (requer `condominium:view`).
  Future<ApiResponse<List<NamedEntityOption>>> listCondominiumsBrief({
    int page = 1,
    int limit = 100,
    String? search,
  }) async {
    final r = await listCondominiumsPage(
      page: page,
      limit: limit,
      search: search,
    );
    if (r.success && r.data != null) {
      return ApiResponse.success(
        data: r.data!.items,
        statusCode: r.statusCode,
      );
    }
    return ApiResponse.error(
      message: r.message ?? 'Erro ao listar condomínios',
      statusCode: r.statusCode,
      data: r.error,
    );
  }

  /// Lista paginada de condomínios com metadata de paginação. Aceita `search`
  /// para filtrar server-side por nome (paridade com `condominiumApi.listCondominiums`
  /// no web). Usada pelo seletor com bottom-sheet do fluxo de criação de imóveis.
  Future<ApiResponse<NamedEntityPage>> listCondominiumsPage({
    int page = 1,
    int limit = 25,
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
      final s = search?.trim();
      if (s != null && s.isNotEmpty) params['search'] = s;
      final response = await _apiService.get<Map<String, dynamic>>(
        '/condominiums',
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: NamedEntityPage.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar condomínios',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] condominiums: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Detalhes do condomínio para pré-popular endereço da propriedade
  /// (paridade `condominiumApi.getCondominiumById`).
  Future<ApiResponse<NamedEntityWithAddress>> getCondominiumById(
    String id,
  ) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/condominiums/$id',
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final map = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: NamedEntityWithAddress.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar condomínio',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] condominium $id: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Detalhes do empreendimento para pré-popular endereço da propriedade
  /// (paridade `empreendimentoApi.getEmpreendimentoById`).
  Future<ApiResponse<NamedEntityWithAddress>> getEmpreendimentoById(
    String id,
  ) async {
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/empreendimentos/$id',
      );
      if (response.success && response.data != null) {
        final raw = response.data!;
        final map = raw['data'] is Map<String, dynamic>
            ? raw['data'] as Map<String, dynamic>
            : raw;
        return ApiResponse.success(
          data: NamedEntityWithAddress.fromJson(map),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar empreendimento',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] empreendimento $id: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Lista mínima para o seletor do wizard (requer permissão de empreendimentos).
  Future<ApiResponse<List<NamedEntityOption>>> listEmpreendimentosBrief({
    int page = 1,
    int limit = 100,
    String? search,
  }) async {
    final r = await listEmpreendimentosPage(
      page: page,
      limit: limit,
      search: search,
    );
    if (r.success && r.data != null) {
      return ApiResponse.success(
        data: r.data!.items,
        statusCode: r.statusCode,
      );
    }
    return ApiResponse.error(
      message: r.message ?? 'Erro ao listar empreendimentos',
      statusCode: r.statusCode,
      data: r.error,
    );
  }

  /// Lista paginada de empreendimentos com metadata de paginação. Aceita `search`
  /// para filtrar server-side por nome.
  Future<ApiResponse<NamedEntityPage>> listEmpreendimentosPage({
    int page = 1,
    int limit = 25,
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
      final s = search?.trim();
      if (s != null && s.isNotEmpty) params['search'] = s;
      final response = await _apiService.get<Map<String, dynamic>>(
        '/empreendimentos',
        queryParameters: params,
      );
      if (response.success && response.data != null) {
        return ApiResponse.success(
          data: NamedEntityPage.fromJson(response.data!),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao listar empreendimentos',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] empreendimentos: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca propriedade por ID
  Future<ApiResponse<Property>> getPropertyById(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Buscando propriedade: $id');

    try {
      final response = await _apiService.get<Map<String, dynamic>>('/properties/$id');

      if (response.success && response.data != null) {
        try {
          final root = _extractPropertyPayload(response.data!);
          if (root == null) {
            return ApiResponse.error(
              message: 'Resposta inválida do servidor.',
              statusCode: response.statusCode,
            );
          }
          final property = Property.fromJson(root);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade encontrada: ${property.title}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Propriedade não encontrada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Cria nova propriedade
  Future<ApiResponse<Property>> createProperty(Map<String, dynamic> data) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Criando propriedade');

    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/properties',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final root = _extractPropertyPayload(response.data!);
          if (root == null) {
            return ApiResponse.error(
              message: 'Resposta inválida ao criar propriedade.',
              statusCode: response.statusCode,
            );
          }
          final property = Property.fromJson(root);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade criada: ${property.id}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao criar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Checagem de duplicidade de endereço antes de cadastrar — mesmo endpoint e
  /// mesmo corpo do `checkDuplicateForCreation` do web (`street`, `number`,
  /// `neighborhood`, `city`, `state` e, quando houver, `condominiumId`,
  /// `propertyUnity`, `complement` (até 100 caracteres) e `type`).
  Future<ApiResponse<PropertyDuplicateCheckResult>> checkDuplicate(
    Map<String, dynamic> payload,
  ) async {
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/properties/duplicate-check',
        body: payload,
      );
      if (response.success && response.data != null) {
        final root = response.data!;
        final duplicates =
            PropertyDuplicateCandidate.listFrom(root['duplicates']);
        return ApiResponse.success(
          data: PropertyDuplicateCheckResult(
            hasDuplicate: root['hasDuplicate'] == true || duplicates.isNotEmpty,
            duplicates: duplicates,
          ),
          statusCode: response.statusCode,
        );
      }
      return ApiResponse.error(
        message: response.message ?? 'Erro ao verificar duplicidade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] duplicate-check: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// `true` quando o `POST /properties` voltou 409 por duplicidade de
  /// endereço (`PROPERTY_DUPLICATE_DETECTED`). O filtro global de exceções do
  /// back devolve só `statusCode`/`errorCode`/`message` — o `code` e a lista
  /// `duplicates` do `ConflictException` somem no caminho —, então a mensagem
  /// fixa do back ("… cadastro duplicado.") também identifica o caso.
  static bool isDuplicateConflict(ApiResponse<dynamic> response) {
    if (response.success || response.statusCode != 409) return false;
    const code = 'PROPERTY_DUPLICATE_DETECTED';
    final body = response.error;
    if (body is Map) {
      if (body['code']?.toString() == code ||
          body['errorCode']?.toString() == code) {
        return true;
      }
      final details = body['details'];
      if (details is Map && details['code']?.toString() == code) return true;
    }
    return (response.message ?? '').toLowerCase().contains('cadastro duplicado');
  }

  /// Candidatos que vierem no corpo do 409 (raiz ou `details`), se vierem.
  static List<PropertyDuplicateCandidate> duplicatesFromConflict(
    ApiResponse<dynamic> response,
  ) {
    final body = response.error;
    if (body is! Map) return const [];
    final direct = PropertyDuplicateCandidate.listFrom(body['duplicates']);
    if (direct.isNotEmpty) return direct;
    final details = body['details'];
    if (details is Map) {
      return PropertyDuplicateCandidate.listFrom(details['duplicates']);
    }
    return const [];
  }

  /// Atualiza propriedade
  Future<ApiResponse<Property>> updateProperty(String id, Map<String, dynamic> data) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Atualizando propriedade: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id',
        body: data,
      );

      if (response.success && response.data != null) {
        try {
          final root = _extractPropertyPayload(response.data!);
          if (root == null) {
            return ApiResponse.error(
              message: 'Resposta inválida ao atualizar propriedade.',
              statusCode: response.statusCode,
            );
          }
          final property = Property.fromJson(root);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade atualizada: ${property.id}');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao atualizar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exclui propriedade
  Future<ApiResponse<void>> deleteProperty(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Excluindo propriedade: $id');

    try {
      final response = await _apiService.delete('/properties/$id');

      if (response.success) {
        debugPrint('✅ [PROPERTY_SERVICE] Propriedade excluída: $id');
        return ApiResponse.success(
          data: null,
          statusCode: response.statusCode,
        );
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao excluir propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Ativa propriedade
  Future<ApiResponse<Property>> activateProperty(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Ativando propriedade: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/activate',
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade ativada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao ativar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Desativa o imóvel — `PATCH /properties/:id/deactivate`, com o mesmo
  /// corpo do `PropertyDeactivationModal` do web (`DeactivatePropertyDto`):
  /// - [reason] é OBRIGATÓRIO: um `value` de [PropertyDeactivationReason]
  ///   (alimenta as métricas da carteira; sem ele o back responde 400 — era
  ///   o que acontecia quando o app mandava o corpo vazio);
  /// - [notes] é opcional (até 2000 caracteres; vazio não vai);
  /// - [scope]: `'all'` (padrão) desativa o cadastro — sai do site e da
  ///   vitrine; `'sale'`/`'rent'` tiram o imóvel só da venda / só da locação:
  ///   a finalidade muda e o imóvel SEGUE ativo (só para finalidade `ambos`;
  ///   o back recusa nos outros casos).
  /// Só master/admin/gestor: o back devolve 403 aos demais.
  Future<ApiResponse<Property>> deactivateProperty(
    String id, {
    required String reason,
    String? notes,
    String scope = 'all',
  }) async {
    final motivo = reason.trim();
    if (motivo.isEmpty) {
      return ApiResponse.error(
        message: 'Selecione o motivo da desativação.',
        statusCode: 400,
      );
    }
    const escoposValidos = {'all', 'sale', 'rent'};
    final escopo = scope.trim().toLowerCase();
    if (!escoposValidos.contains(escopo)) {
      return ApiResponse.error(
        message: 'Escopo de desativação inválido.',
        statusCode: 400,
      );
    }

    debugPrint(
      '🏠 [PROPERTY_SERVICE] Desativando propriedade: $id ($escopo, $motivo)',
    );

    try {
      final body = <String, dynamic>{'reason': motivo, 'scope': escopo};
      final nota = notes?.trim() ?? '';
      if (nota.isNotEmpty) body['notes'] = nota;

      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/deactivate',
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final root =
              _extractPropertyPayload(response.data!) ?? response.data!;
          final property = Property.fromJson(root);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade desativada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao desativar propriedade',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Altera o status do imóvel (transições validadas no backend).
  Future<ApiResponse<Property>> changePropertyStatus(
    String id, {
    required PropertyStatus status,
    String? notes,
  }) async {
    debugPrint(
      '🏠 [PROPERTY_SERVICE] Alterando status da propriedade $id → ${status.value}',
    );

    try {
      final body = <String, dynamic>{'status': status.value};
      if (notes != null && notes.trim().isNotEmpty) {
        body['notes'] = notes.trim();
      }

      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/status',
        body: body,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint(
            '✅ [PROPERTY_SERVICE] Status alterado: $id → ${status.value}',
          );
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao alterar status do imóvel',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Atalho de [changePropertyStatus] com o status CRU, como o web chama
  /// (`propertyApi.changePropertyStatus(id, {status, notes})`):
  /// `PATCH /properties/:id/status`. Status que o app não reconhece nem sai
  /// do aparelho — o back só aceita os 17 do enum.
  Future<ApiResponse<Property>> changeStatus(
    String id,
    String status, {
    String? notes,
  }) async {
    final known = PropertyStatus.fromString(status.replaceAll('-', '_'));
    if (known == null) {
      return ApiResponse.error(
        message: 'Status não reconhecido pelo aplicativo.',
        statusCode: 400,
      );
    }
    return changePropertyStatus(id, status: known, notes: notes);
  }

  /// Republica no site um imóvel que já passou pela publicação e saiu por
  /// algum motivo (manutenção, voltou a rascunho, etc.). Volta para
  /// `AVAILABLE` + ativo + visível no site. As validações finais ficam no
  /// backend (mesma regra do web: `POST /properties/:id/republish`).
  Future<ApiResponse<Property>> republishOnSite(String id) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Republicando no site: $id');
    try {
      final response = await _apiService.post<Map<String, dynamic>>(
        '/properties/$id/republish',
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Imóvel republicado no site: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Não foi possível republicar o imóvel.',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro ao republicar: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Sugestões de localização para o autocomplete da busca — paridade com o
  /// web (`GET /properties/search/location-suggestions`). Retorna lista vazia
  /// silenciosamente em qualquer falha (autocomplete nunca quebra a tela).
  Future<List<PropertyLocationSuggestion>> getLocationSuggestions(
    String query, {
    int limit = 8,
  }) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/search/location-suggestions',
        queryParameters: {'q': q, 'limit': '$limit'},
      );
      if (response.success && response.data != null) {
        final raw = response.data!['suggestions'];
        if (raw is List) {
          return raw
              .whereType<Map<String, dynamic>>()
              .map(PropertyLocationSuggestion.fromJson)
              .toList();
        }
      }
      return const [];
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro ao buscar sugestões: $e');
      return const [];
    }
  }

  /// Marca propriedade como vendida
  Future<ApiResponse<Property>> markAsSold(String id, {String? notes}) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Marcando propriedade como vendida: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/mark-as-sold',
        body: notes != null ? {'notes': notes} : null,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade marcada como vendida: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como vendida',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Marca propriedade como alugada
  Future<ApiResponse<Property>> markAsRented(String id, {String? notes}) async {
    debugPrint('🏠 [PROPERTY_SERVICE] Marcando propriedade como alugada: $id');

    try {
      final response = await _apiService.patch<Map<String, dynamic>>(
        '/properties/$id/mark-as-rented',
        body: notes != null ? {'notes': notes} : null,
      );

      if (response.success && response.data != null) {
        try {
          final property = Property.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Propriedade marcada como alugada: $id');
          return ApiResponse.success(
            data: property,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao marcar como alugada',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca inteligente de propriedades
  Future<ApiResponse<IntelligentSearchResponse>> intelligentSearch({
    String? clientId,
    PropertyType? type,
    String? operation, // 'rent' | 'sale'
    String? city,
    String? state,
    String? neighborhood,
    double? minValue,
    double? maxValue,
    int? minBedrooms,
    int? minBathrooms,
    int? minParkingSpaces,
    double? minArea,
    double? maxArea,
    List<String>? features,
    bool? onlyMyProperties,
    bool? searchInGroupCompanies,
    bool? includeOtherBrokers,
    int page = 1,
    int limit = 50,
  }) async {
    debugPrint('🔍 [PROPERTY_SERVICE] Busca inteligente');

    try {
      final queryParams = <String, dynamic>{
        'page': page.toString(),
        'limit': limit.toString(),
      };

      if (clientId != null) queryParams['clientId'] = clientId;
      if (type != null) queryParams['type'] = type.value;
      if (operation != null) queryParams['operation'] = operation;
      if (city != null) queryParams['city'] = city;
      if (state != null) queryParams['state'] = state;
      if (neighborhood != null) queryParams['neighborhood'] = neighborhood;
      if (minValue != null) queryParams['minValue'] = minValue.toString();
      if (maxValue != null) queryParams['maxValue'] = maxValue.toString();
      if (minBedrooms != null) queryParams['minBedrooms'] = minBedrooms.toString();
      if (minBathrooms != null) queryParams['minBathrooms'] = minBathrooms.toString();
      if (minParkingSpaces != null) queryParams['minParkingSpaces'] = minParkingSpaces.toString();
      if (minArea != null) queryParams['minArea'] = minArea.toString();
      if (maxArea != null) queryParams['maxArea'] = maxArea.toString();
      if (features != null && features.isNotEmpty) queryParams['features'] = features;
      if (onlyMyProperties != null) queryParams['onlyMyProperties'] = onlyMyProperties.toString();
      if (searchInGroupCompanies != null) queryParams['searchInGroupCompanies'] = searchInGroupCompanies.toString();
      if (includeOtherBrokers != null) queryParams['includeOtherBrokers'] = includeOtherBrokers.toString();

      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/search/intelligent',
        queryParameters: queryParams.map((k, v) => MapEntry(k, v.toString())),
      );

      if (response.success && response.data != null) {
        try {
          final searchResponse = IntelligentSearchResponse.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Busca inteligente: ${searchResponse.results.length} resultados');
          return ApiResponse.success(
            data: searchResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro na busca inteligente',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Busca estatísticas de propriedades
  Future<ApiResponse<PropertyStats>> getPropertyStats() async {
    debugPrint('📊 [PROPERTY_SERVICE] Buscando estatísticas');

    try {
      // Endpoint correto: `/properties/statistics` — paridade com o web
      // (`propertyApi.getPropertyStats` em `imobx-front/src/services/propertyApi.ts`).
      // O `companyId` vai pelo header `X-Company-ID` (resolvido pelo `ApiService`),
      // não como query param — antes a rota errada (`/properties/stats`)
      // caía no `:id` do controller e quebrava com "Validation failed (uuid is expected)".
      final response = await _apiService.get<Map<String, dynamic>>(
        '/properties/statistics',
      );

      if (response.success && response.data != null) {
        try {
          final stats = PropertyStats.fromJson(response.data!);
          debugPrint('✅ [PROPERTY_SERVICE] Estatísticas carregadas');
          return ApiResponse.success(
            data: stats,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar dados: ${e.toString()}',
            statusCode: response.statusCode,
            data: response.error,
          );
        }
      }

      return ApiResponse.error(
        message: response.message ?? 'Erro ao buscar estatísticas',
        statusCode: response.statusCode,
        data: response.error,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Exporta propriedades
  Future<ApiResponse<List<int>>> exportProperties({
    String format = 'xlsx', // 'xlsx' | 'csv'
    String? type,
    String? status,
  }) async {
    debugPrint('📤 [PROPERTY_SERVICE] Exportando propriedades (formato: $format)');

    try {
      final queryParams = <String, String>{
        'format': format,
      };
      if (type != null) queryParams['type'] = type;
      if (status != null) queryParams['status'] = status;

      final uri = Uri.parse('${ApiConstants.baseApiUrl}/properties/export')
          .replace(queryParameters: queryParams);

      // Headers padronizados (Authorization + X-Company-ID) — paridade
      // `imobx-front`. Sem o `X-Company-ID`, o backend responde com 400
      // "Usuário deve estar associado a uma empresa".
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: '/properties/export',
      );

      final httpResponse = await http.get(uri, headers: headers).timeout(
            const Duration(seconds: 60),
          );

      if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
        debugPrint('✅ [PROPERTY_SERVICE] Propriedades exportadas');
        return ApiResponse.success(
          data: httpResponse.bodyBytes.toList(),
          statusCode: httpResponse.statusCode,
        );
      }

      return ApiResponse.error(
        message: 'Erro ao exportar propriedades',
        statusCode: httpResponse.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }

  /// Importa propriedades
  Future<ApiResponse<PropertyImportResponse>> importProperties({
    required List<int> fileBytes,
    String? fileName,
    String? format,
  }) async {
    debugPrint('📥 [PROPERTY_SERVICE] Importando propriedades');

    try {
      final uri = Uri.parse('${ApiConstants.baseApiUrl}/properties/import');
      final request = http.MultipartRequest('POST', uri);

      // Headers padronizados — paridade `imobx-front`.
      final headers = await _apiService.buildOutboundHeaders(
        endpoint: '/properties/import',
        excludeContentType: true,
      );
      request.headers.addAll(headers);

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName ?? 'propriedades.xlsx',
        ),
      );
      
      if (format != null) {
        request.fields['format'] = format;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 120),
      );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
          final importResponse = PropertyImportResponse.fromJson(jsonData);
          debugPrint('✅ [PROPERTY_SERVICE] Importação concluída: ${importResponse.success} sucessos, ${importResponse.failed} falhas');
          return ApiResponse.success(
            data: importResponse,
            statusCode: response.statusCode,
          );
        } catch (e) {
          debugPrint('❌ [PROPERTY_SERVICE] Erro ao parsear resposta: $e');
          return ApiResponse.error(
            message: 'Erro ao processar resposta: ${e.toString()}',
            statusCode: response.statusCode,
          );
        }
      }

      return ApiResponse.error(
        message: 'Erro ao importar propriedades',
        statusCode: response.statusCode,
      );
    } catch (e) {
      debugPrint('❌ [PROPERTY_SERVICE] Erro de conexão: $e');
      return ApiResponse.error(
        message: 'Erro de conexão: ${e.toString()}',
        statusCode: 0,
      );
    }
  }
}

/// Resposta de importação de propriedades
class PropertyImportResponse {
  final int total;
  final int success;
  final int failed;
  final List<Property> properties;
  final List<PropertyImportError> errors;
  final bool hasErrorFile;
  final String? errorSpreadsheetBase64;

  PropertyImportResponse({
    required this.total,
    required this.success,
    required this.failed,
    required this.properties,
    required this.errors,
    this.hasErrorFile = false,
    this.errorSpreadsheetBase64,
  });

  factory PropertyImportResponse.fromJson(Map<String, dynamic> json) {
    return PropertyImportResponse(
      total: (json['total'] as num?)?.toInt() ?? 0,
      success: (json['success'] as num?)?.toInt() ?? 0,
      failed: (json['failed'] as num?)?.toInt() ?? 0,
      properties: (json['properties'] as List<dynamic>?)
              ?.map((e) => Property.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => PropertyImportError.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      hasErrorFile: json['hasErrorFile'] as bool? ?? false,
      errorSpreadsheetBase64: json['errorSpreadsheetBase64']?.toString(),
    );
  }
}

class PropertyImportError {
  final int row;
  final String property;
  final List<String> errors;

  PropertyImportError({
    required this.row,
    required this.property,
    required this.errors,
  });

  factory PropertyImportError.fromJson(Map<String, dynamic> json) {
    return PropertyImportError(
      row: (json['row'] as num?)?.toInt() ?? 0,
      property: json['property']?.toString() ?? '',
      errors: (json['errors'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// Resposta de busca inteligente
class IntelligentSearchResponse {
  final List<IntelligentSearchResult> results;
  final int total;
  final int page;
  final int limit;
  final int totalPages;
  final IntelligentSearchStats searchStats;

  IntelligentSearchResponse({
    required this.results,
    required this.total,
    required this.page,
    required this.limit,
    required this.totalPages,
    required this.searchStats,
  });

  factory IntelligentSearchResponse.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchResponse(
      results: (json['results'] as List<dynamic>?)
              ?.map((e) => IntelligentSearchResult.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      total: json['total'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 50,
      totalPages: json['totalPages'] as int? ?? json['total_pages'] as int? ?? 1,
      searchStats: IntelligentSearchStats.fromJson(
        json['searchStats'] as Map<String, dynamic>? ?? {},
      ),
    );
  }
}

class IntelligentSearchResult {
  final Property property;
  final double matchScore;
  final List<String> matchReasons;
  final IntelligentSearchBroker responsibleBroker;
  final IntelligentSearchCompany company;

  IntelligentSearchResult({
    required this.property,
    required this.matchScore,
    required this.matchReasons,
    required this.responsibleBroker,
    required this.company,
  });

  factory IntelligentSearchResult.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchResult(
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      matchScore: (json['matchScore'] as num?)?.toDouble() ?? 0.0,
      matchReasons: (json['matchReasons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      responsibleBroker: IntelligentSearchBroker.fromJson(
        json['responsibleBroker'] as Map<String, dynamic>,
      ),
      company: IntelligentSearchCompany.fromJson(
        json['company'] as Map<String, dynamic>,
      ),
    );
  }
}

class IntelligentSearchBroker {
  final String id;
  final String name;
  final String email;

  IntelligentSearchBroker({
    required this.id,
    required this.name,
    required this.email,
  });

  factory IntelligentSearchBroker.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchBroker(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
    );
  }
}

class IntelligentSearchCompany {
  final String id;
  final String name;

  IntelligentSearchCompany({
    required this.id,
    required this.name,
  });

  factory IntelligentSearchCompany.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchCompany(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }
}

class IntelligentSearchStats {
  final int totalFound;
  final int fromMyProperties;
  final int fromOtherBrokers;
  final int fromGroupCompanies;

  IntelligentSearchStats({
    required this.totalFound,
    required this.fromMyProperties,
    required this.fromOtherBrokers,
    required this.fromGroupCompanies,
  });

  factory IntelligentSearchStats.fromJson(Map<String, dynamic> json) {
    return IntelligentSearchStats(
      totalFound: json['totalFound'] as int? ?? 0,
      fromMyProperties: json['fromMyProperties'] as int? ?? 0,
      fromOtherBrokers: json['fromOtherBrokers'] as int? ?? 0,
      fromGroupCompanies: json['fromGroupCompanies'] as int? ?? 0,
    );
  }
}

/// Estatísticas de propriedades
class PropertyStats {
  final int total;
  final int available;
  final int rented;
  final int sold;
  final Map<String, int> byType;
  final Map<String, int> byStatus;

  PropertyStats({
    required this.total,
    required this.available,
    required this.rented,
    required this.sold,
    required this.byType,
    required this.byStatus,
  });

  factory PropertyStats.fromJson(Map<String, dynamic> json) {
    return PropertyStats(
      total: json['total'] as int? ?? 0,
      available: json['available'] as int? ?? 0,
      rented: json['rented'] as int? ?? 0,
      sold: json['sold'] as int? ?? 0,
      byType: (json['byType'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int? ?? 0)) ??
          {},
      byStatus: (json['byStatus'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v as int? ?? 0)) ??
          {},
    );
  }
}

