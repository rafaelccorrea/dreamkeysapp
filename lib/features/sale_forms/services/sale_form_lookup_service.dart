import 'package:flutter/foundation.dart';

import '../../../core/constants/api_constants.dart';
import '../../../shared/services/api_service.dart';
import '../../workspace/models/company_team_model.dart';
import '../sale_form_property_link.dart';

/// Pessoa simples (id + nome + e-mail) para os seletores da ficha.
class SaleFormPessoa {
  const SaleFormPessoa({required this.id, required this.name, this.email = ''});
  final String id;
  final String name;
  final String email;
}

/// Unidade de venda configurada (`sale_units`).
class SaleFormSaleUnit {
  const SaleFormSaleUnit({required this.id, required this.name});
  final String id;
  final String name;
}

/// `saleUnitId` do payload (web `CreateSaleFormPage.tsx`): id da unidade de
/// venda configurada cujo nome é exatamente o da "Unidade responsável".
String? saleFormSaleUnitIdFor(String saleUnit, List<SaleFormSaleUnit> units) {
  final nome = saleUnit.trim();
  if (nome.isEmpty) return null;
  for (final u in units) {
    if (u.name == nome) return u.id;
  }
  return null;
}

bool? _boolDe(Object? v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().toLowerCase().trim();
  if (s == 'true' || s == '1') return true;
  if (s == 'false' || s == '0') return false;
  return null;
}

/// Filtros de equipe do web sobre o JSON cru de `GET /teams`:
/// - modal de tipo: `useInSaleForms === true`;
/// - "Trocar equipe": `useInSaleForms !== false` e `isPersonal !== true`.
bool saleFormEquipeElegivel(
  Map<String, dynamic> raw, {
  bool paraTrocarEquipe = false,
}) {
  final uso = _boolDe(raw['useInSaleForms']);
  if (!paraTrocarEquipe) return uso == true;
  return uso != false && _boolDe(raw['isPersonal']) != true;
}

/// Consultas auxiliares do formulário da ficha de venda — as mesmas do web:
/// gestores do select "Nome do Gerente" (`getMembersByRole('manager')`) e as
/// unidades compartilhadas de uma ficha (`getSharedUnitIds`).
class SaleFormLookupService {
  SaleFormLookupService._();
  static final SaleFormLookupService instance = SaleFormLookupService._();

  final ApiService _api = ApiService.instance;

  /// `GET /users/company-members?role=manager` (percorre as páginas; o back
  /// limita a 100 por pedido).
  Future<List<SaleFormPessoa>> gestores() async {
    final out = <SaleFormPessoa>[];
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= 10) {
        final res = await _api.get<Map<String, dynamic>>(
          '/users/company-members',
          queryParameters: {'role': 'manager', 'page': '$page', 'limit': '100'},
        );
        if (!res.success || res.data == null) break;
        final raw = res.data!['data'];
        if (raw is List) {
          for (final m in raw.whereType<Map>()) {
            final id = (m['id'] ?? '').toString();
            final name = (m['name'] ?? '').toString().trim();
            if (id.isEmpty || name.isEmpty) continue;
            out.add(SaleFormPessoa(
              id: id,
              name: name,
              email: (m['email'] ?? '').toString(),
            ));
          }
        }
        final tp = res.data!['totalPages'];
        totalPages = tp is num ? tp.toInt() : 1;
        page++;
      }
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] gestores: $e');
    }
    return out;
  }

  /// Catálogo de equipes habilitadas para fichas — igual ao
  /// `SaleFormTypeModal` do web: `GET /teams?useInSaleForms=true`. Com o
  /// parâmetro o back devolve, para quem tem `sale_form:view_all`, TODAS as
  /// equipes habilitadas da empresa (não só as de que participa); sem ele,
  /// um gestor do financeiro via "Nenhuma equipe habilitada"
  /// (`teams.controller.ts`, caso Katia/União de 17/09/2026). Filtra ativas e
  /// habilitadas e ordena por nome, como o web.
  ///
  /// [paraTrocarEquipe] = filtro do "Trocar equipe" do web
  /// (`SaleFormsPage.tsx`): `useInSaleForms !== false` (ausente vale) e sem
  /// equipes pessoais (`isPersonal`). Sem ele, o do modal de tipo
  /// (`useInSaleForms === true`).
  Future<ApiResponse<List<CompanyTeam>>> equipesDeFichas({
    bool paraTrocarEquipe = false,
  }) async {
    try {
      final res = await _api.get<dynamic>(
        ApiConstants.teams,
        queryParameters: const {'useInSaleForms': 'true'},
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao carregar equipes.',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      final teams = (list is List ? list : const [])
          .whereType<Map>()
          .where((m) => saleFormEquipeElegivel(
                Map<String, dynamic>.from(m),
                paraTrocarEquipe: paraTrocarEquipe,
              ))
          .map((m) => CompanyTeam.fromJson(Map<String, dynamic>.from(m)))
          .where((t) => t.id.isNotEmpty && t.isActive)
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return ApiResponse.success(data: teams, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] equipesDeFichas: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Busca de imóvel por código para o vínculo oficial — web:
  /// `propertyApi.getProperties({ code }, { page: 1, limit: 20 })`
  /// (`GET /properties?code=…`), sem vendidos/alugados.
  Future<ApiResponse<List<SaleFormPropertyHit>>> buscarImoveisPorCodigo(
    String code,
  ) async {
    try {
      final res = await _api.get<dynamic>(
        '/properties',
        queryParameters: {
          'code': code.trim(),
          'onlyMyData': 'false',
          'page': '1',
          'limit': '20',
        },
      );
      if (!res.success) {
        return ApiResponse.error(
          message: res.message ?? 'Erro ao buscar imóveis.',
          statusCode: res.statusCode,
        );
      }
      final raw = res.data;
      final list = raw is List
          ? raw
          : (raw is Map
              ? (raw['data'] is List
                  ? raw['data'] as List
                  : (raw['properties'] is List
                      ? raw['properties'] as List
                      : const []))
              : const []);
      final hits = list
          .whereType<Map>()
          .map((m) => SaleFormPropertyHit.fromJson(Map<String, dynamic>.from(m)))
          .where((h) => h.id.isNotEmpty && saleFormPropertyLinkable(h.status))
          .toList();
      return ApiResponse.success(data: hits, statusCode: res.statusCode);
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] buscarImoveisPorCodigo: $e');
      return ApiResponse.error(message: e.toString(), statusCode: 0);
    }
  }

  /// Status atual do imóvel vinculado (`propertyApi.getPropertyById`) para o
  /// aviso "vira Vendido ao concluir". `null` quando não foi possível obter.
  Future<String?> statusDoImovel(String propertyId) async {
    try {
      final res = await _api.get<dynamic>('/properties/${propertyId.trim()}');
      if (!res.success) return null;
      final raw = res.data;
      final m = raw is Map && raw['data'] is Map ? raw['data'] : raw;
      if (m is! Map) return null;
      final s = (m['status'] ?? '').toString().trim();
      return s.isEmpty ? null : s;
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] statusDoImovel: $e');
      return null;
    }
  }

  /// Unidades de venda configuradas da empresa (`useSaleUnits({activeOnly})`
  /// do web → `GET /sistema/sale-units-config?activeOnly=true`). Usadas só
  /// para mandar `saleUnitId` quando o nome da "Unidade responsável" casa com
  /// uma delas. Falha = lista vazia (o back deduz pela `saleUnit`).
  Future<List<SaleFormSaleUnit>> unidadesDeVenda() async {
    try {
      final res = await _api.get<dynamic>(
        '/sistema/sale-units-config',
        queryParameters: const {'activeOnly': 'true'},
      );
      if (!res.success) return const [];
      final raw = res.data;
      final list = raw is List ? raw : (raw is Map ? raw['data'] : null);
      return (list is List ? list : const [])
          .whereType<Map>()
          .map((m) => SaleFormSaleUnit(
                id: (m['id'] ?? '').toString(),
                name: (m['name'] ?? '').toString(),
              ))
          .where((u) => u.id.isNotEmpty && u.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] unidadesDeVenda: $e');
      return const [];
    }
  }

  /// `GET /sistema/fichas-venda/:id/unidades-compartilhadas` → `{unitIds}`.
  /// `null` quando falha (quem chama NÃO deve enviar `sharedUnitIds`, para não
  /// apagar o compartilhamento gravado).
  Future<List<String>?> unidadesCompartilhadas(String saleFormId) async {
    try {
      final res = await _api.get<dynamic>(
        '${ApiConstants.saleFormById(saleFormId)}/unidades-compartilhadas',
      );
      if (!res.success) return null;
      final data = res.data;
      final ids = data is Map ? data['unitIds'] : null;
      if (ids is! List) return const [];
      return ids.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (e) {
      debugPrint('[SALE_FORM_LOOKUP] unidadesCompartilhadas: $e');
      return null;
    }
  }
}
