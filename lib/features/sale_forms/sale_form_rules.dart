import 'package:flutter/services.dart';

// Regras da ficha de venda — espelho 1:1 do web (`CreateSaleFormPage.tsx`:
// `computeErrorsForTab`, `getCommissionInstallmentValuesError`, TABS e
// `saleFormNotApplicable.ts`). O web é a fonte da verdade: mesmas chaves,
// mesmas mensagens, mesma ordem. Arquivo puro (sem widgets) para poder ser
// conferido linha a linha contra o web.

/// Valor gravado quando o campo foi marcado como "Não aplicável".
const String kSaleFormNa = 'Não aplicável';

/// Rótulo da opção nos selects (o valor continua sendo [kSaleFormNa]).
const String kSaleFormNaSelectLabel = '― Não aplicável ―';

/// `isSaleFormNotApplicable` do web: "Não aplicável" ou "N/A" (qualquer caixa).
bool isSaleFormNa(String? value) {
  if (value == null) return false;
  final t = value.trim();
  if (t.isEmpty) return false;
  if (t == kSaleFormNa) return true;
  return t.toUpperCase() == 'N/A';
}

String saleFormDigits(String? v) => (v ?? '').replaceAll(RegExp(r'\D'), '');

/// `getNumericValue` do web para textos mascarados em pt-BR ("1.234,56").
double saleFormNumeric(String? v) {
  final clean = (v ?? '').replaceAll(RegExp(r'[^\d,]'), '');
  if (clean.isEmpty) return 0;
  return double.tryParse(clean.replaceAll(',', '.')) ?? 0;
}

bool saleFormValidCpf(String doc) {
  final c = saleFormDigits(doc);
  if (c.length != 11) return false;
  if (RegExp(r'^(\d)\1{10}$').hasMatch(c)) return false;
  int dv(int len) {
    var sum = 0;
    for (var i = 0; i < len; i++) {
      sum += int.parse(c[i]) * (len + 1 - i);
    }
    var r = (sum * 10) % 11;
    if (r == 10 || r == 11) r = 0;
    return r;
  }

  return dv(9) == int.parse(c[9]) && dv(10) == int.parse(c[10]);
}

/// CNPJ numérico ou alfanumérico (mesmo cálculo do web: valor = ASCII - 48).
bool saleFormValidCnpj(String doc) {
  final c = doc.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (c.length != 14) return false;
  int dv(String base) {
    const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final start = 13 - base.length;
    var sum = 0;
    for (var i = 0; i < base.length; i++) {
      sum += (base.codeUnitAt(i) - 48) * weights[start + i];
    }
    final r = sum % 11;
    return r == 0 || r == 1 ? 0 : 11 - r;
  }

  final dv1 = int.tryParse(c[12]);
  final dv2 = int.tryParse(c[13]);
  if (dv1 == null || dv2 == null) return false;
  return dv(c.substring(0, 12)) == dv1 && dv(c.substring(0, 13)) == dv2;
}

bool saleFormValidCpfOuCnpj(String doc) {
  final d = saleFormDigits(doc);
  if (d.length == 11) return saleFormValidCpf(doc);
  if (d.length == 14) return saleFormValidCnpj(doc);
  return false;
}

bool saleFormValidEmail(String email) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim());

bool saleFormValidPhone(String phone) {
  final d = saleFormDigits(phone);
  return d.length >= 10 && d.length <= 11;
}

bool saleFormValidCep(String cep) => saleFormDigits(cep).length == 8;

/// Abas do web. Lançamento/MCMV não têm Vendedor (3) nem Cônjuge Vendedor (4).
const List<int> kSaleFormTabsTodas = [0, 1, 2, 3, 4, 5, 6, 7, 8];
const List<int> kSaleFormTabsLancamento = [0, 1, 2, 5, 6, 7, 8];

/// Campos de erro de cada aba (`TAB_FIELD_KEYS`) — para limpar erro antigo.
const Map<int, List<String>> kSaleFormTabFieldKeys = {
  0: [
    'teamId', 'saleDate', 'secretaryPresent', 'managerName', 'mediaSource',
    'saleUnit', 'description',
  ],
  1: [
    'buyerName', 'buyerCpf', 'buyerRg', 'buyerBirthDate', 'buyerProfession',
    'buyerEmail', 'buyerPhone', 'buyerZipCode', 'buyerStreet', 'buyerNumber',
    'buyerNeighborhood', 'buyerCity', 'buyerState',
  ],
  2: [
    'buyerSpouseName', 'buyerSpouseCpf', 'buyerSpouseRg',
    'buyerSpouseBirthDate', 'buyerSpouseProfession', 'buyerSpouseEmail',
    'buyerSpousePhone', 'buyerSpouseZipCode', 'buyerSpouseStreet',
    'buyerSpouseNumber', 'buyerSpouseNeighborhood', 'buyerSpouseCity',
    'buyerSpouseState',
  ],
  3: [
    'sellerName', 'sellerCpf', 'sellerRg', 'sellerBirthDate',
    'sellerProfession', 'sellerEmail', 'sellerPhone', 'sellerZipCode',
    'sellerStreet', 'sellerNumber', 'sellerNeighborhood', 'sellerCity',
    'sellerState',
  ],
  4: [
    'sellerSpouseName', 'sellerSpouseCpf', 'sellerSpouseRg',
    'sellerSpouseBirthDate', 'sellerSpouseProfession', 'sellerSpouseEmail',
    'sellerSpousePhone', 'sellerSpouseZipCode', 'sellerSpouseStreet',
    'sellerSpouseNumber', 'sellerSpouseNeighborhood', 'sellerSpouseCity',
    'sellerSpouseState',
  ],
  5: [
    'incorporadora', 'empreendimento', 'unidade', 'dataEntrada',
    'valorEntrada', 'formaPagamento', 'propertyCode', 'propertyZipCode',
    'propertyAddress', 'propertyNumber', 'propertyNeighborhood',
    'propertyCity', 'propertyState', 'commissionPaymentModel',
    'commissionPaymentModelDescription', 'saleValue', 'totalCommission',
    'goalValue', 'preAtendimento', 'centralCaptacao',
    'commissionInstallmentsCount', 'commissionInstallmentValues',
    'debtConfession', 'debtConfessionValue', 'fullFinancing',
  ],
  6: [],
  7: [],
  8: [],
};

/// Limite do back (`ParcelamentoComissaoDto.quantidadeParcelas`).
const int kSaleFormMaxParcelas = 120;

String _brl(double v) {
  final s = v.toStringAsFixed(2);
  return 'R\$ $s';
}

/// `getCommissionInstallmentValuesError` do web (null = ok).
String? saleFormInstallmentValuesError(
  List<String> values,
  int qtd,
  String totalCommission,
) {
  final totalCents = (saleFormNumeric(totalCommission) * 100).round();
  final cents = [
    for (var i = 0; i < qtd; i++)
      (saleFormNumeric(i < values.length ? values[i] : '') * 100).round(),
  ];
  if (totalCents > 0 && cents.any((v) => v > totalCents)) {
    return 'Nenhuma parcela pode ser maior que a Comissão Total '
        '(${_brl(totalCents / 100)})';
  }
  if (cents.any((v) => v <= 0)) return 'Preencha o valor de todas as parcelas';
  final soma = cents.fold<int>(0, (a, b) => a + b);
  if ((soma - totalCents).abs() > 1) {
    return 'A soma das parcelas (${_brl(soma / 100)}) deve bater com a '
        'Comissão Total (${_brl(totalCents / 100)})';
  }
  return null;
}

/// Estado do formulário no formato do web (chaves do `FormData`).
/// Datas: ISO `yyyy-MM-dd`; sim/não: `'sim'`/`'nao'`/`''`; N/A: [kSaleFormNa].
class SaleFormRulesInput {
  const SaleFormRulesInput({
    required this.fd,
    required this.hasBuyerSpouse,
    required this.hasSellerSpouse,
    required this.generalGroup,
    required this.isLancamentoOuMcmv,
    required this.commissionModelNaoAplicavel,
    required this.installmentsEnabled,
    required this.installmentsEqual,
    required this.installmentValues,
    required this.fichaAnteriorAosCamposNovos,
  });

  final Map<String, String> fd;
  final bool hasBuyerSpouse;
  final bool hasSellerSpouse;
  final bool generalGroup;
  final bool isLancamentoOuMcmv;
  final bool commissionModelNaoAplicavel;
  final bool installmentsEnabled;
  final bool installmentsEqual;
  final List<String> installmentValues;

  /// Ficha criada antes de 18/09/2026 (sem resposta gravada): não cobra
  /// confissão de dívida nem financiamento 100%.
  final bool fichaAnteriorAosCamposNovos;

  String v(String k) => fd[k] ?? '';
}

/// `computeErrorsForTab` do web — erros da aba, na ordem do web.
Map<String, String> computeSaleFormErrorsForTab(
  int tabId,
  SaleFormRulesInput i,
) {
  final e = <String, String>{};
  String v(String k) => i.v(k);
  bool na(String k) => isSaleFormNa(v(k));

  /// Obrigatório ou N/A.
  void req(String k, String msg) {
    if (!na(k) && v(k).trim().isEmpty) e[k] = msg;
  }

  /// Obrigatório (por dígitos) + formato, ou N/A.
  void fmt(
    String k,
    String obrigatorio,
    String invalido,
    bool Function(String) valido, {
    bool porDigitos = true,
  }) {
    if (na(k)) return;
    final vazio = porDigitos ? saleFormDigits(v(k)).isEmpty : v(k).trim().isEmpty;
    if (vazio) {
      e[k] = obrigatorio;
    } else if (!valido(v(k))) {
      e[k] = invalido;
    }
  }

  switch (tabId) {
    case 0:
      if (v('teamId').trim().isEmpty) e['teamId'] = 'Equipe da ficha é obrigatória';
      req('saleDate', 'Data da venda é obrigatória');
      req('secretaryPresent', 'Informe se a secretária estava presente');
      req('managerName', 'Selecione o gerente responsável');
      if (v('mediaSource').trim().isEmpty) {
        e['mediaSource'] = 'Mídia de origem é obrigatória';
      }
      req('saleUnit', 'Unidade de venda é obrigatória');
      req(
        'description',
        i.generalGroup
            ? 'Descrição da forma de comissionamento é obrigatória quando a ficha é de unidade compartilhada'
            : 'Descrição da operação é obrigatória',
      );
    case 1:
      req('buyerName', 'Nome do comprador é obrigatório');
      fmt('buyerCpf', 'CPF ou CNPJ do comprador é obrigatório',
          'CPF ou CNPJ inválido', saleFormValidCpfOuCnpj);
      req('buyerRg', 'RG do comprador é obrigatório');
      req('buyerBirthDate', 'Data de nascimento é obrigatória');
      req('buyerProfession', 'Profissão é obrigatória');
      fmt('buyerEmail', 'E-mail é obrigatório', 'E-mail inválido',
          saleFormValidEmail,
          porDigitos: false);
      fmt('buyerPhone', 'Celular é obrigatório',
          'Telefone inválido (mín. 10 dígitos)', saleFormValidPhone);
      fmt('buyerZipCode', 'CEP é obrigatório', 'CEP inválido (8 dígitos)',
          saleFormValidCep);
      req('buyerStreet', 'Rua é obrigatória');
      req('buyerNumber', 'Número é obrigatório');
      req('buyerNeighborhood', 'Bairro é obrigatório');
      req('buyerCity', 'Cidade é obrigatória');
      req('buyerState', 'Estado é obrigatório');
    case 2:
      if (!i.hasBuyerSpouse) break;
      _conjuge('buyerSpouse', req, fmt);
    case 3:
      req('sellerName', 'Nome do vendedor é obrigatório');
      fmt('sellerCpf', 'CPF ou CNPJ do vendedor é obrigatório',
          'CPF ou CNPJ inválido', saleFormValidCpfOuCnpj);
      req('sellerRg', 'RG do vendedor é obrigatório');
      req('sellerBirthDate', 'Data de nascimento é obrigatória');
      req('sellerProfession', 'Profissão é obrigatória');
      fmt('sellerEmail', 'E-mail é obrigatório', 'E-mail inválido',
          saleFormValidEmail,
          porDigitos: false);
      fmt('sellerPhone', 'Celular é obrigatório', 'Telefone inválido',
          saleFormValidPhone);
      fmt('sellerZipCode', 'CEP é obrigatório', 'CEP inválido',
          saleFormValidCep);
      req('sellerStreet', 'Rua é obrigatória');
      req('sellerNumber', 'Número é obrigatório');
      req('sellerNeighborhood', 'Bairro é obrigatório');
      req('sellerCity', 'Cidade é obrigatória');
      req('sellerState', 'Estado é obrigatório');
    case 4:
      if (!i.hasSellerSpouse) break;
      _conjuge('sellerSpouse', req, fmt);
    case 5:
      if (i.isLancamentoOuMcmv) {
        req('incorporadora', 'Incorporadora é obrigatória');
        req('empreendimento', 'Empreendimento é obrigatório');
        req('unidade', 'Unidade é obrigatória');
        req('dataEntrada', 'Data da entrada é obrigatória');
        if (!na('valorEntrada')) {
          if (v('valorEntrada').trim().isEmpty) {
            e['valorEntrada'] = 'Valor da entrada é obrigatório';
          } else if (saleFormNumeric(v('valorEntrada')) < 0) {
            e['valorEntrada'] = 'Valor da entrada não pode ser negativo';
          }
        }
        req('formaPagamento', 'Forma de pagamento é obrigatória');
      } else {
        req('propertyCode', 'Código do imóvel é obrigatório');
        fmt('propertyZipCode', 'CEP do imóvel é obrigatório', 'CEP inválido',
            saleFormValidCep);
        req('propertyAddress', 'Endereço do imóvel é obrigatório');
        req('propertyNumber', 'Número é obrigatório');
        req('propertyNeighborhood', 'Bairro é obrigatório');
        req('propertyCity', 'Cidade é obrigatória');
        req('propertyState', 'Estado é obrigatório');
      }
      if (!na('saleValue') && saleFormNumeric(v('saleValue')) <= 0) {
        e['saleValue'] = 'Valor da venda é obrigatório';
      }
      if (!i.commissionModelNaoAplicavel) {
        if (v('commissionPaymentModelDescription').trim().isEmpty) {
          e['commissionPaymentModelDescription'] =
              'Descreva o modelo de pagamento da comissão ou marque Não aplicável.';
        }
        if (!na('totalCommission')) {
          if (v('totalCommission').trim().isEmpty) {
            e['totalCommission'] = 'Comissão total é obrigatória';
          } else if (saleFormNumeric(v('totalCommission')) < 0) {
            e['totalCommission'] = 'Comissão total não pode ser negativa';
          }
        }
        if (!na('goalValue')) {
          if (v('goalValue').trim().isEmpty) {
            e['goalValue'] = 'Valor da meta é obrigatório';
          } else if (saleFormNumeric(v('goalValue')) < 0) {
            e['goalValue'] = 'Valor da meta não pode ser negativo';
          }
        }
        if (i.installmentsEnabled) {
          final qtd = int.tryParse(v('commissionInstallmentsCount').trim());
          if (qtd == null || qtd < 2) {
            e['commissionInstallmentsCount'] =
                'Informe a quantidade de parcelas (mínimo 2)';
          } else if (qtd > kSaleFormMaxParcelas) {
            // Trava do back (ParcelamentoComissaoDto) — antecipada aqui.
            e['commissionInstallmentsCount'] =
                'Quantidade de parcelas excede o limite permitido';
          } else if (!i.installmentsEqual) {
            final err = saleFormInstallmentValuesError(
              i.installmentValues,
              qtd,
              v('totalCommission'),
            );
            if (err != null) e['commissionInstallmentValues'] = err;
          }
        }
      }
      if (v('debtConfession').isEmpty) {
        if (!i.fichaAnteriorAosCamposNovos) {
          e['debtConfession'] =
              'Informe se a imobiliária paga a confissão de dívida';
        }
      } else if (v('debtConfession') == 'sim' &&
          saleFormNumeric(v('debtConfessionValue')) <= 0) {
        e['debtConfessionValue'] = 'Informe o valor da confissão de dívida';
      }
      if (v('fullFinancing').isEmpty && !i.fichaAnteriorAosCamposNovos) {
        e['fullFinancing'] = 'Informe se o financiamento é 100%';
      }
      req('preAtendimento', 'Pré-atendimento é obrigatório');
      req('centralCaptacao', 'Central de captação é obrigatória');
    default:
      break;
  }
  return e;
}

/// Abas 2 e 4 do web (cônjuge/sócio ligado): tudo obrigatório ou N/A.
void _conjuge(
  String p,
  void Function(String, String) req,
  void Function(String, String, String, bool Function(String),
          {bool porDigitos})
      fmt,
) {
  req('${p}Name',
      'Nome do cônjuge é obrigatório quando “Possui cônjuge/sócio” está marcado');
  fmt('${p}Cpf', 'CPF do cônjuge é obrigatório', 'CPF inválido',
      saleFormValidCpf);
  req('${p}Rg', 'RG do cônjuge é obrigatório');
  req('${p}BirthDate', 'Data de nascimento do cônjuge é obrigatória');
  req('${p}Profession', 'Profissão do cônjuge é obrigatória');
  fmt('${p}Email', 'E-mail do cônjuge é obrigatório', 'E-mail inválido',
      saleFormValidEmail,
      porDigitos: false);
  fmt('${p}Phone', 'Celular do cônjuge é obrigatório', 'Telefone inválido',
      saleFormValidPhone);
  fmt('${p}ZipCode', 'CEP do cônjuge é obrigatório', 'CEP inválido',
      saleFormValidCep);
  req('${p}Street', 'Rua é obrigatória');
  req('${p}Number', 'Número é obrigatório');
  req('${p}Neighborhood', 'Bairro é obrigatório');
  req('${p}City', 'Cidade é obrigatória');
  req('${p}State', 'Estado é obrigatório');
}

// ─── Máscaras (mesmas do web) ───────────────────────────────────────────────

String saleFormMaskCpf(String digits) {
  final d = digits.length > 11 ? digits.substring(0, 11) : digits;
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 3 || i == 6) b.write('.');
    if (i == 9) b.write('-');
    b.write(d[i]);
  }
  return b.toString();
}

String saleFormMaskCnpj(String digits) {
  final d = digits.length > 14 ? digits.substring(0, 14) : digits;
  final b = StringBuffer();
  for (var i = 0; i < d.length; i++) {
    if (i == 2 || i == 5) b.write('.');
    if (i == 8) b.write('/');
    if (i == 12) b.write('-');
    b.write(d[i]);
  }
  return b.toString();
}

/// `maskCPFouCNPJ`: até 11 dígitos = CPF, depois CNPJ.
String saleFormMaskCpfOuCnpj(String v) {
  final d = saleFormDigits(v);
  return d.length <= 11 ? saleFormMaskCpf(d) : saleFormMaskCnpj(d);
}

/// `maskPhoneAuto`: (00) 0000-0000 até 10 dígitos, (00) 00000-0000 com 11.
String saleFormMaskPhone(String v) {
  var d = saleFormDigits(v);
  if (d.length >= 12 && d.startsWith('55')) d = d.substring(d.length - 11);
  if (d.length > 11) d = d.substring(0, 11);
  if (d.isEmpty) return '';
  if (d.length <= 2) return '($d';
  final ddd = d.substring(0, 2);
  final rest = d.substring(2);
  final corte = d.length == 11 ? 5 : 4;
  if (rest.length <= corte) return '($ddd) $rest';
  return '($ddd) ${rest.substring(0, corte)}-${rest.substring(corte)}';
}

String saleFormMaskCep(String v) {
  var d = saleFormDigits(v);
  if (d.length > 8) d = d.substring(0, 8);
  return d.length <= 5 ? d : '${d.substring(0, 5)}-${d.substring(5)}';
}

/// Máscara por tipo de campo.
enum SaleFormMask { none, cpfOuCnpj, cpf, phone, cep, email }

String saleFormApplyMask(SaleFormMask m, String v) => switch (m) {
      SaleFormMask.none => v,
      SaleFormMask.cpfOuCnpj => saleFormMaskCpfOuCnpj(v),
      SaleFormMask.cpf => saleFormMaskCpf(saleFormDigits(v)),
      SaleFormMask.phone => saleFormMaskPhone(v),
      SaleFormMask.cep => saleFormMaskCep(v),
      // `maskEmail`: sem espaços, minúsculas.
      SaleFormMask.email => v.replaceAll(RegExp(r'\s'), '').toLowerCase(),
    };

/// Como o `applyMask` do web: "N/A" (qualquer caixa) vira "Não aplicável";
/// senão aplica a máscara do campo.
class SaleFormFieldFormatter extends TextInputFormatter {
  SaleFormFieldFormatter(this.mask);
  final SaleFormMask mask;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (isSaleFormNa(newValue.text)) {
      return const TextEditingValue(
        text: kSaleFormNa,
        selection: TextSelection.collapsed(offset: kSaleFormNa.length),
      );
    }
    if (mask == SaleFormMask.none) return newValue;
    final masked = saleFormApplyMask(mask, newValue.text);
    if (masked == newValue.text) return newValue;
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}
