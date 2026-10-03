/// Vínculo oficial da ficha de venda com o imóvel do cadastro — espelha o
/// `CreateSaleFormPage.tsx` do web (`buscarPropriedadesPorCodigo`,
/// `selecionarPropriedade`, `propertyToSaleFormImovel` e o aviso
/// `linkedPropertyFinalizeNotice`).
///
/// Com `propertyId` gravado, ao concluir as assinaturas o back tenta marcar
/// o imóvel como Vendido (`PropertyService.applySoldFromSaleFormFinalization`).
library;

/// Status do cadastro em que o back marca o imóvel como Vendido ao finalizar
/// a ficha (`PROPERTY_STATUSES_AUTO_SOLD_ON_FORM_FINALIZED` do web).
const Set<String> kSaleFormAutoSoldStatuses = {
  'available',
  'rented',
  'maintenance',
  'pending_approval',
  'pending_owner_authorization',
  'pending_publication',
};

/// Rótulo pt-BR dos status (`PropertyStatusOptions` do web).
const Map<String, String> kSaleFormPropertyStatusLabels = {
  'draft': 'Rascunho',
  'pending_owner_authorization': 'Aguardando autorização do proprietário',
  'pending_approval': 'Aguardando aprovação',
  'pending_publication': 'Aguardando publicação no site',
  'available': 'Disponível',
  'in_service': 'Em Atendimento',
  'visit_scheduled': 'Visita Agendada',
  'in_visit': 'Em Visita',
  'in_negotiation': 'Em Negociação',
  'proposal_received': 'Proposta Recebida',
  'registration_analysis': 'Análise Cadastral',
  'documentation': 'Documentação',
  'contract_drafting': 'Contrato em Elaboração',
  'signature': 'Assinatura',
  'rented': 'Alugado',
  'sold': 'Vendido',
  'maintenance': 'Manutenção',
};

String saleFormPropertyStatusLabel(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return kSaleFormPropertyStatusLabels[s] ?? s;
}

/// A busca do web esconde imóvel vendido ou alugado (o back recusa o vínculo:
/// "Não é possível vincular imóvel já vendido ou alugado.").
bool saleFormPropertyLinkable(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  return s != 'sold' && s != 'rented';
}

/// Imóvel achado pela busca por código, no recorte que a ficha usa.
class SaleFormPropertyHit {
  const SaleFormPropertyHit({
    required this.id,
    required this.code,
    required this.zipCode,
    required this.address,
    required this.number,
    required this.complement,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.status,
    this.title,
  });

  final String id;
  final String code;

  /// Só dígitos (8).
  final String zipCode;
  final String address;
  final String number;
  final String complement;
  final String neighborhood;
  final String city;
  final String state;
  final String? status;
  final String? title;

  /// `propertyToSaleFormImovel` do web, com os mesmos padrões
  /// (CEP `00000000`, número `S/N`, UF `SP`, código = id).
  factory SaleFormPropertyHit.fromJson(Map<String, dynamic> j) {
    String s(dynamic v) => (v ?? '').toString().trim();
    String? sn(dynamic v) {
      final t = s(v);
      return t.isEmpty ? null : t;
    }

    var zip = s(j['zipCode']).replaceAll(RegExp(r'\D'), '');
    if (zip.length > 8) zip = zip.substring(0, 8);
    if (zip.isEmpty) zip = '00000000';
    var uf = s(j['state']).toUpperCase();
    if (uf.length > 2) uf = uf.substring(0, 2);
    return SaleFormPropertyHit(
      id: s(j['id']),
      code: sn(j['code']) ?? s(j['id']),
      zipCode: zip,
      address: sn(j['address']) ?? s(j['street']),
      number: sn(j['number']) ?? 'S/N',
      complement: s(j['complement']),
      neighborhood: s(j['neighborhood']),
      city: s(j['city']),
      state: uf.isEmpty ? 'SP' : uf,
      status: sn(j['status']),
      title: sn(j['title']),
    );
  }

  /// "Rua X, 120 · Bairro · Cidade/UF".
  String get resumo {
    final rua = [address, number].where((e) => e.isNotEmpty).join(', ');
    final local = [city, state].where((e) => e.isNotEmpty).join('/');
    return [rua, neighborhood, local].where((e) => e.isNotEmpty).join(' · ');
  }
}

/// `propertyId` do payload (web): ao criar, só vai quando há vínculo; ao
/// editar, vai sempre — `null` desfaz o vínculo (o código foi trocado à mão).
/// Retorna `(incluir, valor)`.
(bool, String?) saleFormPropertyIdPayload({
  required bool isEdit,
  required String? propertyId,
}) {
  final id = (propertyId ?? '').trim();
  if (id.isNotEmpty) return (true, id);
  return isEdit ? (true, null) : (false, null);
}

/// Situação do aviso de vínculo (`linkedPropertyFinalizeNotice`).
enum SaleFormLinkedNoticeTone { info, warn }

class SaleFormLinkedNotice {
  const SaleFormLinkedNotice(this.tone, this.situacao);
  final SaleFormLinkedNoticeTone tone;
  final String situacao;
}

/// Texto da situação conforme o status atual do imóvel vinculado.
/// `status == null` e `loading == false` = não foi possível consultar.
SaleFormLinkedNotice saleFormLinkedPropertyNotice({
  required String? status,
  required bool loading,
}) {
  final st = (status ?? '').trim().toLowerCase();
  if (loading) {
    return const SaleFormLinkedNotice(SaleFormLinkedNoticeTone.info,
        'Consultando o status do imóvel no cadastro…');
  }
  if (st.isEmpty) {
    return const SaleFormLinkedNotice(
      SaleFormLinkedNoticeTone.info,
      'Não foi possível obter o status atual do imóvel. Na finalização da '
      'ficha, a tentativa de marcar como Vendido seguirá a mesma regra, '
      'conforme o status registrado no servidor naquele momento.',
    );
  }
  final label = saleFormPropertyStatusLabel(st);
  if (st == 'sold') {
    return SaleFormLinkedNotice(
      SaleFormLinkedNoticeTone.info,
      'Situação atual: $label. O cadastro já está como vendido; ao concluir '
      'as assinaturas não é necessária alteração automática de status.',
    );
  }
  if (kSaleFormAutoSoldStatuses.contains(st)) {
    return SaleFormLinkedNotice(
      SaleFormLinkedNoticeTone.info,
      'Situação atual: $label. Neste status, ao concluir todas as '
      'assinaturas o sistema marcará o imóvel como Vendido automaticamente.',
    );
  }
  if (st == 'draft') {
    return SaleFormLinkedNotice(
      SaleFormLinkedNoticeTone.warn,
      'Situação atual: $label. A ficha pode ser finalizada, mas o imóvel não '
      'será atualizado para Vendido automaticamente enquanto estiver em '
      'rascunho. Publique ou ajuste o status do cadastro antes da '
      'finalização, ou altere manualmente depois.',
    );
  }
  return SaleFormLinkedNotice(
    SaleFormLinkedNoticeTone.warn,
    'Situação atual: $label. Esse status não está na lista em que o sistema '
    'atualiza o cadastro para Vendido sozinho; a ficha pode finalizar, mas o '
    'imóvel não será alterado automaticamente — ajuste manualmente se '
    'necessário.',
  );
}
