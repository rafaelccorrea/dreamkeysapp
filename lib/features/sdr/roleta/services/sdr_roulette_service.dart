import 'package:flutter/foundation.dart';

import '../../../../shared/services/api_service.dart';
import '../models/sdr_availability.dart';
import '../models/sdr_roulette_rules.dart';

/// Roleta de SDRs (disponibilidade, pausa, folga agendada, SDR de locação) —
/// os mesmos endpoints do imobx-front (`whatsappApi.ts`, "SDR Availability")
/// e do `WhatsAppController` do back:
///   - `GET    /whatsapp/sdr-availability`
///   - `PATCH  /whatsapp/sdr-availability/:userId/toggle`
///     `{isActive, pauseReason?}`
///   - `POST   /whatsapp/sdr-availability/:userId/schedule-pause`
///     `{pauseStart, pauseEnd, pauseReason}` (ISO 8601)
///   - `DELETE /whatsapp/sdr-availability/:userId/schedule-pause`
///   - `PATCH  /whatsapp/sdr-availability/:userId/so-locacao` `{soLocacao}`
///     → `{userId, soLocacao}`
///
/// Nunca relança: toda falha volta como [ApiResponse.error] com a mensagem
/// do back intacta — ela explica a regra (403 de quem não é líder/admin,
/// "pelo menos 1 SDR ativo", datas inválidas).
class SdrRouletteService {
  SdrRouletteService._();

  static final SdrRouletteService instance = SdrRouletteService._();
  final ApiService _api = ApiService.instance;

  static const String _base = '/whatsapp/sdr-availability';
  static const String _toggle = '/toggle';
  static const String _schedulePause = '/schedule-pause';
  static const String _soLocacao = '/so-locacao';

  String _doSdr(String userId, String sufixo) {
    return '$_base/${Uri.encodeComponent(userId)}$sufixo';
  }

  /// Mensagem vazia ou o "Erro desconhecido" do [ApiService] não explicam
  /// nada: entra o texto do web para a mesma falha.
  ApiResponse<T> _fail<T>(ApiResponse<dynamic> r, String fallback) {
    final m = r.message?.trim() ?? '';
    final especifica = m.isNotEmpty && m != 'Erro desconhecido';
    return ApiResponse.error(
      message: especifica ? m : fallback,
      statusCode: r.statusCode,
      data: r.error,
    );
  }

  ApiResponse<T> _exception<T>(String onde, Object e) {
    debugPrint('[SDR_ROLETA] $onde: $e');
    return ApiResponse.error(
      message: 'Erro de conexão: ${e.toString()}',
      statusCode: 0,
    );
  }

  /// Lista os SDRs da equipe do WhatsApp com a situação de cada um. O back
  /// processa antes as folgas que começaram ou terminaram.
  Future<ApiResponse<List<SdrAvailability>>> list() async {
    try {
      final r = await _api.get<dynamic>(_base);
      if (!r.success) {
        return _fail(r, 'Erro ao carregar disponibilidade dos SDRs');
      }
      final raw = r.data;
      final List<dynamic> lista = raw is List
          ? raw
          : (raw is Map && raw['data'] is List)
              ? raw['data'] as List<dynamic>
              : const <dynamic>[];
      final itens = <SdrAvailability>[];
      for (final e in lista) {
        if (e is! Map) continue;
        final item = SdrAvailability.fromJson(Map<String, dynamic>.from(e));
        if (item.userId.isNotEmpty) itens.add(item);
      }
      return ApiResponse.success(data: itens, statusCode: r.statusCode);
    } catch (e) {
      return _exception('list', e);
    }
  }

  /// Liga ou tira o SDR da roleta à mão. Pausar manda o motivo padrão do web
  /// ("Pausado manualmente"); ligar vai só com `isActive`.
  Future<ApiResponse<void>> toggle(
    String userId, {
    required bool isActive,
    String? pauseReason,
  }) async {
    try {
      final body = <String, dynamic>{
        'isActive': isActive,
        if (!isActive && pauseReason != null) 'pauseReason': pauseReason,
      };
      final r = await _api.patch<dynamic>(
        _doSdr(userId, _toggle),
        body: body,
      );
      if (r.success) {
        return ApiResponse.success(data: null, statusCode: r.statusCode);
      }
      return _fail(r, 'Erro ao alterar disponibilidade');
    } catch (e) {
      return _exception('toggle', e);
    }
  }

  /// Agenda a folga: sai da roleta no início e volta sozinho no fim. Início
  /// já passado = a pausa começa na hora (o back valida o último ativo).
  Future<ApiResponse<void>> schedulePause(
    String userId, {
    required DateTime start,
    required DateTime end,
    required String reason,
  }) async {
    try {
      final r = await _api.post<dynamic>(
        _doSdr(userId, _schedulePause),
        body: <String, dynamic>{
          'pauseStart': start.toUtc().toIso8601String(),
          'pauseEnd': end.toUtc().toIso8601String(),
          'pauseReason': reason,
        },
      );
      if (r.success) {
        return ApiResponse.success(data: null, statusCode: r.statusCode);
      }
      return _fail(r, 'Erro ao agendar folga');
    } catch (e) {
      return _exception('schedulePause', e);
    }
  }

  /// Cancela a folga agendada (se ela já estiver em curso, o SDR volta).
  Future<ApiResponse<void>> cancelScheduledPause(String userId) async {
    try {
      final r = await _api.delete<dynamic>(_doSdr(userId, _schedulePause));
      if (r.success) {
        return ApiResponse.success(data: null, statusCode: r.statusCode);
      }
      return _fail(r, 'Erro ao cancelar folga agendada');
    } catch (e) {
      return _exception('cancelScheduledPause', e);
    }
  }

  /// Marca/desmarca o SDR de locação. Devolve o valor salvo pelo back.
  Future<ApiResponse<bool>> setSoLocacao(String userId, bool soLocacao) async {
    try {
      final r = await _api.patch<dynamic>(
        _doSdr(userId, _soLocacao),
        body: <String, dynamic>{'soLocacao': soLocacao},
      );
      if (r.success) {
        final raw = r.data;
        final salvo = (raw is Map && raw['soLocacao'] is bool)
            ? raw['soLocacao'] as bool
            : soLocacao;
        return ApiResponse.success(data: salvo, statusCode: r.statusCode);
      }
      return _fail(r, SdrRouletteRules.erroAoMarcarLocacao);
    } catch (e) {
      return _exception('setSoLocacao', e);
    }
  }
}
