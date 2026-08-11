import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../shared/services/company_service.dart';
import '../../shared/services/secure_storage_service.dart';

/// Guardião ÚNICO do bootstrap de sessão.
///
/// ── POR QUE ISTO EXISTE ────────────────────────────────────────────────
/// Uma sessão utilizável no app tem DUAS partes: o token (gravado no login)
/// e o `companyId` (gravado só DEPOIS, quando alguém carrega `/companies` e
/// escolhe a empresa preferida). Toda rota protegida exige o header
/// `X-Company-ID` — sem ele o [ApiService] bloqueia a requisição e a tela
/// mostra "Company ID não encontrado. Por favor, selecione uma empresa.".
///
/// O bug de produção era uma CORRIDA: vários caminhos chegavam à Home (ou a
/// uma tela de destino) com token mas ainda SEM `companyId`:
///   1. login biométrico — entrava direto na Home sem passar pelo
///      `LoginFlowService`, que é quem carrega as empresas;
///   2. toque em push / deep link — empurrava a rota enquanto o splash
///      ainda estava resolvendo a empresa;
///   3. cold start em geral — a Home dispara requisições no `initState`.
/// O paliativo anterior (polling cego de 500ms–2s dentro do `ApiService`)
/// não resolvia porque, se ninguém tivesse MANDADO carregar as empresas, o
/// ID nunca ia aparecer — por mais que se esperasse.
///
/// Aqui a espera é ATIVA: quem chega primeiro dispara a resolução, e todos
/// os outros aguardam o MESMO future (idempotente, sem carga duplicada).
class SessionBootstrap {
  SessionBootstrap._();

  static final SessionBootstrap instance = SessionBootstrap._();

  bool _ready = false;
  bool _userHasNoCompany = false;
  Future<bool>? _inFlight;

  /// Sessão completa (token + empresa resolvida) pronta para uso.
  bool get isReady => _ready;

  /// `true` só quando o servidor confirmou que o utilizador REALMENTE não
  /// tem nenhuma empresa. É o único caso em que a mensagem de erro de
  /// empresa é legítima — nunca por corrida de inicialização.
  bool get userHasNoCompany => _userHasNoCompany;

  /// Açúcar para quem só quer esperar sem olhar o resultado.
  Future<void> get whenReady => ensureReady().then((_) {});

  /// Garante token válido **e** `companyId` resolvido.
  ///
  /// Idempotente e seguro para chamadas concorrentes: enquanto uma
  /// resolução está em curso, todos recebem o mesmo future — nunca duas
  /// cargas de `/companies` em paralelo.
  ///
  /// [timeout] limita a espera de QUEM CHAMA (a resolução continua em
  /// background); sem ele, espera o quanto for preciso.
  Future<bool> ensureReady({Duration? timeout}) {
    if (_ready) return Future<bool>.value(true);

    // `??=` garante que concorrentes compartilhem exatamente o mesmo future.
    final pending = _inFlight ??= _resolve().whenComplete(() {
      _inFlight = null;
    });

    if (timeout == null) return pending;
    return pending.timeout(timeout, onTimeout: () {
      debugPrint(
        '⏱️ [SESSION] ensureReady excedeu ${timeout.inSeconds}s — seguindo sem empresa',
      );
      return false;
    });
  }

  Future<bool> _resolve() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token == null || token.isEmpty) {
        // Sem token não há o que preparar. NÃO marcamos ready: o próximo
        // login chama de novo e a resolução acontece aí.
        debugPrint('ℹ️ [SESSION] Sem token — sessão não inicializada');
        return false;
      }

      final existing = await SecureStorageService.instance.getCompanyId();
      if (existing != null && existing.isNotEmpty) {
        _ready = true;
        _userHasNoCompany = false;
        return true;
      }

      debugPrint('🔄 [SESSION] Token sem empresa — resolvendo empresa preferida...');
      final selection =
          await CompanyService.instance.resolveAndPersistPreferredCompany();

      final id = selection.companyId;
      if (id != null && id.isNotEmpty) {
        _ready = true;
        _userHasNoCompany = false;
        debugPrint('✅ [SESSION] Sessão pronta — empresa $id');
        return true;
      }

      // Falha de rede não vira "usuário sem empresa": nesse caso a próxima
      // chamada tenta de novo em vez de cravar um diagnóstico errado.
      _userHasNoCompany = selection.userHasNoCompany;
      debugPrint(
        '⚠️ [SESSION] Empresa não resolvida '
        '(semEmpresa=${selection.userHasNoCompany}, falhou=${selection.failed})',
      );
      return false;
    } catch (e, stackTrace) {
      debugPrint('❌ [SESSION] Erro ao preparar sessão: $e');
      debugPrint('📚 [SESSION] StackTrace: $stackTrace');
      return false;
    }
  }

  /// Marca a sessão como pronta quando quem chamou JÁ resolveu e gravou a
  /// empresa (é o caso do `LoginFlowService`) — evita uma segunda ida a
  /// `/companies` logo após o login.
  void markReady() {
    _ready = true;
    _userHasNoCompany = false;
  }

  /// Zera o estado. Obrigatório no logout: o próximo utilizador (ou o mesmo
  /// entrando por biometria) precisa resolver a empresa outra vez.
  void reset() {
    _ready = false;
    _userHasNoCompany = false;
    _inFlight = null;
    debugPrint('🧹 [SESSION] Estado de sessão reiniciado');
  }
}
