/// Quando reconsultar a trava de assinatura parada.
///
/// Paridade com o `SignatureLockGate` do web: consulta a cada troca de tela
/// (rota de página, não diálogo/folha), menos nas telas que o web pula
/// (`skipRoutes`: raiz, login/recuperação de senha e as telas das fichas de
/// venda e de locação — é lá que o usuário resolve a pendência). Também na
/// Home e ao voltar o app para o primeiro plano.
///
/// O contador de avisos do back sobe no máximo uma vez por dia por ficha
/// (`sale-forms.service.ts`, `isSameUtcDay`), então consultar a cada tela não
/// "gasta" avisos; o intervalo mínimo abaixo só junta rajadas (abrir e fechar
/// telas em sequência) numa consulta.
library;

const Duration kSignatureLockIntervaloMinimo = Duration(seconds: 2);

/// `true` quando já passou [intervalo] desde a [ultima] consulta.
bool signatureLockPodeConsultar(
  DateTime? ultima,
  DateTime agora, {
  Duration intervalo = kSignatureLockIntervaloMinimo,
}) {
  if (ultima == null) return true;
  return agora.difference(ultima) >= intervalo;
}

/// Rotas nomeadas exatas que o web pula (`/`, `/login`, recuperação de
/// senha, 2FA).
const Set<String> _kRotasIgnoradasExatas = {
  '/',
  '/login',
  '/forgot-password',
  '/forgot-password-confirmation',
  '/reset-password',
  '/two-factor',
};

/// Prefixos que o web pula (`/fichas-venda…`, `/ficha-locacao…`).
const List<String> _kPrefixosIgnorados = ['/sale-forms', '/rental-forms'];

/// `true` = não consultar a trava ao entrar nesta rota nomeada. Rota sem
/// nome não é ignorada por aqui (as telas de ficha sem nome se marcam com
/// `SignatureLockWatcher.marcarTelaDeFicha`).
bool signatureLockRotaIgnorada(String? nome) {
  final n = (nome ?? '').trim();
  if (n.isEmpty) return false;
  final semQuery = n.split('?').first;
  if (_kRotasIgnoradasExatas.contains(semQuery)) return true;
  return _kPrefixosIgnorados.any(
    (p) => semQuery == p || semQuery.startsWith('$p/'),
  );
}
