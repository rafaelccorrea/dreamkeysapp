/// Catálogo de seções e campos da ficha de locação — port fiel do
/// `RentalLocacaoFormBody.tsx` (web). As CHAVES e OPÇÕES são idênticas às do
/// web: o payload gravado pelo app precisa render o mesmo PDF e a mesma página
/// pública. Máscaras seguem o padrão do app (`input_formatters.dart`), mas o
/// VALOR salvo espelha o formato do web (ex.: moeda com prefixo `R$ `).
library;

/// Abas do formulário (blocos do payload).
enum RentalSectionKey { inquilino, fiador, proprietario }

extension RentalSectionKeyX on RentalSectionKey {
  String get payloadKey {
    switch (this) {
      case RentalSectionKey.inquilino:
        return 'inquilino';
      case RentalSectionKey.fiador:
        return 'fiador';
      case RentalSectionKey.proprietario:
        return 'proprietario';
    }
  }

  String get label {
    switch (this) {
      case RentalSectionKey.inquilino:
        return 'Inquilino';
      case RentalSectionKey.fiador:
        return 'Fiador';
      case RentalSectionKey.proprietario:
        return 'Proprietário';
    }
  }

  String get hint {
    switch (this) {
      case RentalSectionKey.inquilino:
        return 'Quem vai morar no imóvel';
      case RentalSectionKey.fiador:
        return 'Garantidor da locação';
      case RentalSectionKey.proprietario:
        return 'Titular do imóvel';
    }
  }
}

/// Tipo de controle/máscara do campo.
enum RentalFieldType {
  text,
  multiline,
  cpf,
  cnpj,
  rg,
  phone,
  cep,
  email,
  date, // dd/mm/aaaa como TEXTO (mesmo formato do web)
  money, // salvo com prefixo 'R$ ' (paridade maskCurrencyReais)
  number,
  select,
  multiSelect, // salvo como join ', ' (paridade normalizedSelectValue)
  checkbox, // salvo como 'Aceito' | ''
  moradores, // JSON [{nome, telefone, cpf}] na chave moradoresAdultosLista
}

class RentalField {
  final String key;
  final String label;
  final RentalFieldType type;
  final String? hint;
  final List<String>? options;

  /// Ocupa a linha inteira (senão o layout tenta parear em 2 colunas).
  final bool full;

  const RentalField(
    this.key,
    this.label,
    this.type, {
    this.hint,
    this.options,
    this.full = false,
  });
}

class RentalFormSection {
  final String id;
  final String title;
  final String? hint;
  final List<RentalField> fields;

  const RentalFormSection({
    required this.id,
    required this.title,
    this.hint,
    required this.fields,
  });
}

// ─── Opções (idênticas ao web) ──────────────────────────────────────────────

const List<String> kRentalUfs = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS',
  'MG', 'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC',
  'SP', 'SE', 'TO',
];

const List<String> kEstadoCivilOptions = [
  'Solteiro(a)',
  'Casado(a)',
  'Divorciado(a)',
  'Viúvo(a)',
  'União estável',
  'Separado(a)',
];

const List<String> kNacionalidadeOptions = [
  'Brasileiro(a)',
  'Naturalizado(a)',
  'Argentina',
  'Boliviana',
  'Chilena',
  'Colombiana',
  'Paraguaia',
  'Peruana',
  'Uruguaia',
  'Venezuelana',
  'Portuguesa',
  'Estados Unidos',
  'Outra',
];

const List<String> kSimNaoOptions = ['Sim', 'Não'];

const List<String> kFinalidadeOptions = [
  'Residencial',
  'Comercial',
  'Temporada',
  'Outro',
];

const List<String> kTipoContaOptions = ['Conta Corrente', 'Conta Poupança'];

const List<String> kTipoInquilinoOptions = ['Pessoa Física', 'Pessoa Jurídica'];

const List<String> kRelacaoDocumentosOptions = [
  'RG',
  'CPF',
  'CNH',
  'Comprovante de renda',
  'Comprovante de residência',
  'Carteira de trabalho',
  'Declaração de IR',
  'Extrato bancário',
  'Certidão de casamento',
  'Contrato social',
  'Cartão CNPJ',
];

/// Chave da lista dinâmica de moradores maiores de 18 (JSON).
const String kMoradoresAdultosListKey = 'moradoresAdultosLista';

// ─── Campos ────────────────────────────────────────────────────────────────

const _nomeCompleto =
    RentalField('nomeCompleto', 'Nome completo', RentalFieldType.text,
        hint: 'Como no documento', full: true);
const _cpf = RentalField('cpf', 'CPF', RentalFieldType.cpf);
const _rg = RentalField('rg', 'RG', RentalFieldType.rg);
const _nacionalidade = RentalField(
    'nacionalidade', 'Nacionalidade', RentalFieldType.select,
    options: kNacionalidadeOptions);
const _estadoCivil = RentalField(
    'estadoCivil', 'Estado civil', RentalFieldType.select,
    options: kEstadoCivilOptions);
const _dataNascimento = RentalField(
    'dataNascimento', 'Data de nascimento', RentalFieldType.date,
    hint: 'dd/mm/aaaa');

const _email = RentalField('email', 'E-mail', RentalFieldType.email);
const _telefone = RentalField('telefone', 'Telefone', RentalFieldType.phone);
const _celular = RentalField('celular', 'Celular', RentalFieldType.phone);

const _cep = RentalField('cep', 'CEP', RentalFieldType.cep);
const _endereco = RentalField('endereco', 'Logradouro', RentalFieldType.text,
    hint: 'Rua, avenida…', full: true);
const _numero = RentalField('numero', 'Número', RentalFieldType.text);
const _complemento =
    RentalField('complemento', 'Complemento', RentalFieldType.text);
const _bairro = RentalField('bairro', 'Bairro', RentalFieldType.text);
const _cidade = RentalField('cidade', 'Cidade', RentalFieldType.text);
const _estado = RentalField('estado', 'UF', RentalFieldType.select,
    options: kRentalUfs);

const _profissao =
    RentalField('profissao', 'Profissão', RentalFieldType.text);
const _rendaMensal =
    RentalField('rendaMensal', 'Renda mensal', RentalFieldType.money);
const _outrasRendas =
    RentalField('outrasRendas', 'Outras rendas', RentalFieldType.money);
const _empresa = RentalField(
    'empresa', 'Empresa (onde trabalha)', RentalFieldType.text,
    full: true);
const _empresaTelefone = RentalField(
    'empresaTelefone', 'Telefone da empresa', RentalFieldType.phone);
const _empresaEndereco = RentalField(
    'empresaEndereco', 'Logradouro da empresa', RentalFieldType.text,
    full: true);
const _empresaNumero =
    RentalField('empresaNumero', 'Número da empresa', RentalFieldType.text);
const _empresaComplemento = RentalField(
    'empresaComplemento', 'Complemento da empresa', RentalFieldType.text);
const _empresaBairro =
    RentalField('empresaBairro', 'Bairro da empresa', RentalFieldType.text);
const _empresaCidade =
    RentalField('empresaCidade', 'Cidade da empresa', RentalFieldType.text);
const _empresaEstado = RentalField(
    'empresaEstado', 'UF da empresa', RentalFieldType.select,
    options: kRentalUfs);
const _tempoServico =
    RentalField('tempoServico', 'Tempo de serviço', RentalFieldType.text);

const _conjugeNomeCompleto = RentalField(
    'conjugeNomeCompleto', 'Nome completo do cônjuge', RentalFieldType.text,
    full: true);
const _conjugeCpf =
    RentalField('conjugeCpf', 'CPF do cônjuge', RentalFieldType.cpf);
const _conjugeCelular = RentalField(
    'conjugeCelular', 'Celular do cônjuge', RentalFieldType.phone);

const _inquilinoTipoCadastro = RentalField('inquilinoTipoCadastro',
    'Tipo de cadastro do inquilino', RentalFieldType.select,
    options: kTipoInquilinoOptions, full: true);
const _filiacao = RentalField('filiacao', 'Filiação', RentalFieldType.text,
    full: true);
const _moraAluguel = RentalField(
    'moraAluguel', 'Mora de aluguel?', RentalFieldType.select,
    options: kSimNaoOptions);
const _motivoAluguel = RentalField('motivoAluguel',
    'Motivo de aluguel / mudança', RentalFieldType.multiline,
    full: true);
const _qtdMoradoresAdultos = RentalField('quantidadeMoradoresAdultos',
    'Moradores acima de 18 anos', RentalFieldType.number,
    hint: 'Ex.: 2');
const _moradoresAdultosLista = RentalField(kMoradoresAdultosListKey,
    'Moradores maiores de 18 anos', RentalFieldType.moradores,
    full: true);
const _qtdMoradoresMenores = RentalField('quantidadeMoradoresMenores',
    'Moradores abaixo de 18 anos', RentalFieldType.number,
    hint: 'Ex.: 1');
const _possuiPets = RentalField(
    'possuiPets', 'Possui pets?', RentalFieldType.select,
    options: kSimNaoOptions);
const _qtdPets = RentalField(
    'quantidadePets', 'Quantidade de pets', RentalFieldType.number);
const _racaPets =
    RentalField('racaPets', 'Raça dos pets', RentalFieldType.text);
const _whatsappBoleto = RentalField(
    'whatsappBoleto', 'WhatsApp para boleto', RentalFieldType.phone);
const _emailBoleto = RentalField(
    'emailBoleto', 'E-mail para boleto', RentalFieldType.email);

const _nomePJ = RentalField(
    'nome', 'Nome / Razão social', RentalFieldType.text,
    full: true);
const _dataAbertura = RentalField(
    'dataAbertura', 'Data de abertura', RentalFieldType.date,
    hint: 'dd/mm/aaaa');
const _cnpj = RentalField('cnpj', 'CNPJ', RentalFieldType.cnpj);
const _socioAdministrador = RentalField(
    'socioAdministrador', 'Sócio administrador', RentalFieldType.text,
    full: true);
const _estadoCivilSocio = RentalField('estadoCivilSocioAdministrador',
    'Estado civil do sócio', RentalFieldType.select,
    options: kEstadoCivilOptions);
const _cpfSocio = RentalField(
    'cpfSocioAdministrador', 'CPF do sócio', RentalFieldType.cpf);

const _enderecoImovelContrato = RentalField('enderecoImovelContrato',
    'Endereço do imóvel', RentalFieldType.text,
    full: true);
const _valorAluguelContrato = RentalField(
    'valorAluguelContrato', 'Valor do aluguel', RentalFieldType.money);
const _prazoContrato = RentalField(
    'prazoContrato', 'Prazo de contrato', RentalFieldType.text,
    hint: 'Ex.: 30 meses');
const _vencimentoAluguel = RentalField(
    'vencimentoAluguel', 'Vencimento do aluguel', RentalFieldType.text,
    hint: 'Ex.: todo dia 10');
const _finalidadeContrato = RentalField(
    'finalidadeContrato', 'Finalidade', RentalFieldType.select,
    options: kFinalidadeOptions);
const _tarifaBoleto = RentalField(
    'tarifaBoleto', 'Tarifa boleto (R\$)', RentalFieldType.money);
const _assinaturaDigital = RentalField('assinaturaDigital',
    'Assinatura digital (R\$/assinatura)', RentalFieldType.money);

const _refLocatario1 = RentalField('referenciaLocatarioPessoal',
    'Referência pessoal', RentalFieldType.text);
const _refLocatario1Fone = RentalField('referenciaLocatarioFone',
    'Fone da referência', RentalFieldType.phone);
const _refLocatario2 = RentalField('referenciaLocatarioPessoal2',
    'Referência pessoal 2', RentalFieldType.text);
const _refLocatario2Fone = RentalField('referenciaLocatarioFone2',
    'Fone da referência 2', RentalFieldType.phone);

const _refFiador1 =
    RentalField('refPessoal', 'Referência pessoal', RentalFieldType.text);
const _refFiador1Fone = RentalField(
    'refPessoalFone', 'Fone ref. pessoal', RentalFieldType.phone);
const _refFiador2 = RentalField(
    'refPessoal2', 'Referência pessoal 2', RentalFieldType.text);
const _refFiador2Fone = RentalField(
    'refPessoalFone2', 'Fone ref. pessoal 2', RentalFieldType.phone);

const _propriedadesFiador = RentalField('propriedadesFiador',
    'Propriedades do fiador', RentalFieldType.multiline,
    hint: 'Descreva os imóveis/propriedades', full: true);

const _tipoContaCredito = RentalField(
    'tipoContaCredito', 'Tipo de conta', RentalFieldType.select,
    options: kTipoContaOptions);
const _bancoCredito =
    RentalField('bancoCredito', 'Banco', RentalFieldType.text);
const _agenciaCredito =
    RentalField('agenciaCredito', 'Agência', RentalFieldType.text);
const _contaCredito =
    RentalField('contaCredito', 'Conta corrente', RentalFieldType.text);
const _pix = RentalField('pix', 'PIX', RentalFieldType.text);
const _beneficiarioCredito = RentalField('beneficiarioCredito',
    'Nome do beneficiário', RentalFieldType.text,
    full: true);

const _relacaoDocumentos = RentalField('relacaoDocumentos',
    'Relação de documentos', RentalFieldType.multiSelect,
    options: kRelacaoDocumentosOptions, full: true);
const _confirmacaoVeracidade = RentalField('confirmacaoVeracidade',
    'Confirmo a veracidade dos dados informados', RentalFieldType.checkbox,
    full: true);

// ─── Seções ────────────────────────────────────────────────────────────────

const _sectionDocumentos = RentalFormSection(
  id: 'documentos',
  title: 'Identificação e documentos',
  hint: 'Nome e CPF como constam no documento de identidade.',
  fields: [_nomeCompleto, _cpf, _rg, _nacionalidade, _estadoCivil, _dataNascimento],
);

const _sectionContato = RentalFormSection(
  id: 'contato',
  title: 'Contato',
  hint: 'Informe o e-mail e pelo menos um telefone com DDD.',
  fields: [_email, _telefone, _celular],
);

const _sectionEndereco = RentalFormSection(
  id: 'endereco',
  title: 'Endereço residencial',
  hint: 'Endereço completo com CEP para comprovação cadastral.',
  fields: [_cep, _endereco, _numero, _complemento, _bairro, _cidade, _estado],
);

const _sectionTrabalho = RentalFormSection(
  id: 'trabalho',
  title: 'Profissão, renda e trabalho',
  hint: 'Campos opcionais — preencha o que tiver para análise cadastral.',
  fields: [
    _profissao,
    _rendaMensal,
    _outrasRendas,
    _empresa,
    _empresaTelefone,
    _empresaEndereco,
    _empresaNumero,
    _empresaComplemento,
    _empresaBairro,
    _empresaCidade,
    _empresaEstado,
    _tempoServico,
  ],
);

const _sectionInquilinoComplementar = RentalFormSection(
  id: 'inquilino-complementar',
  title: 'Dados complementares do inquilino',
  hint: 'Informações adicionais solicitadas para análise da locação.',
  fields: [
    _inquilinoTipoCadastro,
    _filiacao,
    _moraAluguel,
    _motivoAluguel,
    _qtdMoradoresAdultos,
    _moradoresAdultosLista,
    _qtdMoradoresMenores,
    _possuiPets,
    _qtdPets,
    _racaPets,
    _whatsappBoleto,
    _emailBoleto,
  ],
);

const _sectionInquilinoPJ = RentalFormSection(
  id: 'inquilino-pj',
  title: 'Inquilino pessoa jurídica',
  hint: 'Use este bloco quando o inquilino for pessoa jurídica.',
  fields: [
    _nomePJ,
    _dataAbertura,
    _cnpj,
    _socioAdministrador,
    _estadoCivilSocio,
    _cpfSocio,
  ],
);

RentalFormSection _conjugeSection(String title) => RentalFormSection(
      id: 'conjuge',
      title: title,
      hint: 'Informe os dados do cônjuge quando houver.',
      fields: const [_conjugeNomeCompleto, _conjugeCpf, _conjugeCelular],
    );

const _sectionContrato = RentalFormSection(
  id: 'contrato',
  title: 'Dados do contrato',
  hint: 'Preenchimento obrigatório pela imobiliária para envio do link.',
  fields: [
    _enderecoImovelContrato,
    _valorAluguelContrato,
    _prazoContrato,
    _vencimentoAluguel,
    _finalidadeContrato,
    _tarifaBoleto,
    _assinaturaDigital,
  ],
);

const _sectionReferenciasLocatario = RentalFormSection(
  id: 'referencias-locatario',
  title: 'Referências do locatário',
  fields: [_refLocatario1, _refLocatario1Fone, _refLocatario2, _refLocatario2Fone],
);

const _sectionFiadorRefs = RentalFormSection(
  id: 'referencias',
  title: 'Referências do fiador',
  hint: 'Informe uma referência pessoal.',
  fields: [_refFiador1, _refFiador1Fone, _refFiador2, _refFiador2Fone],
);

const _sectionPropriedadesFiador = RentalFormSection(
  id: 'propriedades-fiador',
  title: 'Propriedades do fiador',
  fields: [_propriedadesFiador],
);

const _sectionCreditoProprietario = RentalFormSection(
  id: 'credito-proprietario',
  title: 'Dados para crédito dos aluguéis',
  hint: 'Conta bancária para repasse do aluguel ao proprietário.',
  fields: [
    _tipoContaCredito,
    _bancoCredito,
    _agenciaCredito,
    _contaCredito,
    _pix,
    _beneficiarioCredito,
  ],
);

const _sectionDocumentacao = RentalFormSection(
  id: 'documentacao-anexos',
  title: 'Relação de documentos',
  hint: 'Anexos de arquivos são enviados pelo link público ou pelo painel web.',
  fields: [_relacaoDocumentos, _confirmacaoVeracidade],
);

/// Seções exibidas por aba — mesma composição do web (`sectionsForTab`).
/// Para o inquilino, `isPJ` troca o bloco de documentos PF pelo PJ.
List<RentalFormSection> rentalSectionsForTab(
  RentalSectionKey tab, {
  bool isPJ = false,
}) {
  switch (tab) {
    case RentalSectionKey.inquilino:
      return [
        _sectionInquilinoComplementar,
        if (isPJ) _sectionInquilinoPJ else _sectionDocumentos,
        _sectionContato,
        _sectionEndereco,
        _sectionTrabalho,
        _conjugeSection('Dados do cônjuge do inquilino'),
        _sectionContrato,
        _sectionReferenciasLocatario,
        _sectionDocumentacao,
      ];
    case RentalSectionKey.fiador:
      return [
        _sectionDocumentos,
        _sectionContato,
        _sectionEndereco,
        _sectionTrabalho,
        _conjugeSection('Dados do cônjuge do fiador'),
        _sectionContrato,
        _sectionFiadorRefs,
        _sectionPropriedadesFiador,
        _sectionDocumentacao,
      ];
    case RentalSectionKey.proprietario:
      return [
        _sectionDocumentos,
        _sectionContato,
        _sectionEndereco,
        _conjugeSection('Dados do cônjuge do proprietário'),
        _sectionCreditoProprietario,
        _sectionDocumentacao,
      ];
  }
}

// ─── Obrigatoriedade (paridade com BASE_REQUIRED_BY_TAB do web) ────────────

const List<String> _contractRequiredKeys = [
  'enderecoImovelContrato',
  'valorAluguelContrato',
  'prazoContrato',
  'vencimentoAluguel',
  'finalidadeContrato',
  'tarifaBoleto',
  'assinaturaDigital',
];

const List<String> _pjRequiredKeys = [
  'nome',
  'dataAbertura',
  'cnpj',
  'endereco',
  'socioAdministrador',
  'estadoCivilSocioAdministrador',
  'cpfSocioAdministrador',
];

const Map<RentalSectionKey, List<String>> _baseRequiredByTab = {
  RentalSectionKey.inquilino: [
    'nomeCompleto',
    'dataNascimento',
    'cpf',
    'estadoCivil',
    'nacionalidade',
    'celular',
    'email',
    'quantidadeMoradoresAdultos',
    'possuiPets',
    'confirmacaoVeracidade',
  ],
  RentalSectionKey.fiador: [
    'nomeCompleto',
    'dataNascimento',
    'cpf',
    'estadoCivil',
    'nacionalidade',
    'celular',
    'email',
    'confirmacaoVeracidade',
  ],
  RentalSectionKey.proprietario: [
    'nomeCompleto',
    'dataNascimento',
    'cpf',
    'estadoCivil',
    'celular',
    'email',
    'tipoContaCredito',
    'bancoCredito',
    'agenciaCredito',
    'contaCredito',
    'beneficiarioCredito',
    'confirmacaoVeracidade',
  ],
};

/// Chaves obrigatórias da aba no perfil `editor` — o mesmo do web: base +
/// dados do contrato (inquilino/fiador); no inquilino PJ, contrato + bloco PJ.
List<String> rentalRequiredKeysForTab(
  RentalSectionKey tab,
  Map<String, String> data,
) {
  if (tab == RentalSectionKey.inquilino &&
      (data['inquilinoTipoCadastro'] ?? '') == 'Pessoa Jurídica') {
    return [..._contractRequiredKeys, ..._pjRequiredKeys, 'confirmacaoVeracidade'];
  }
  final keys = [..._baseRequiredByTab[tab]!];
  if (tab == RentalSectionKey.inquilino || tab == RentalSectionKey.fiador) {
    keys.addAll(_contractRequiredKeys);
  }
  return keys.toSet().toList();
}

/// A aba "começou" a ser preenchida? (aba vazia não é exigida — paridade web).
bool rentalSectionHasContent(Map<String, String> data) {
  return data.values.any((v) => v.trim().isNotEmpty);
}
