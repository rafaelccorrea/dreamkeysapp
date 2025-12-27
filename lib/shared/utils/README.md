# 📚 Utilitários Compartilhados

Este diretório contém utilitários reutilizáveis para validações, máscaras e formatação de dados.

## 📋 Estrutura

```
utils/
├── validators.dart        # Validações reutilizáveis
├── masks.dart            # Máscaras de formatação
└── input_formatters.dart # Formatters para TextFields
```

## 🔍 Validators (`validators.dart`)

Sistema completo de validações reutilizáveis.

### Uso Básico

```dart
import 'package:dreamkeys_corretor_app/shared/utils/validators.dart';

// Validação de email
String? emailValidator(String? value) {
  return Validators.requiredEmail(value);
}

// Validação de senha
String? passwordValidator(String? value) {
  return Validators.password(value, minLength: 8);
}

// Validação de CPF
String? cpfValidator(String? value) {
  return Validators.cpf(value);
}
```

### Validações Disponíveis

- `required()` - Campo obrigatório
- `email()` - Validação de email
- `requiredEmail()` - Email obrigatório com validação
- `password()` - Validação de senha com tamanho mínimo
- `confirmPassword()` - Confirmação de senha
- `cpf()` - Validação de CPF com dígitos verificadores
- `cnpj()` - Validação de CNPJ com dígitos verificadores
- `phone()` - Validação de telefone/celular
- `cep()` - Validação de CEP
- `minLength()` - Tamanho mínimo
- `maxLength()` - Tamanho máximo
- `number()` - Validação de número
- `money()` - Validação de valor monetário
- `url()` - Validação de URL
- `custom()` - Validação customizada
- `combine()` - Combinar múltiplas validações

### Exemplos

```dart
// Validação customizada com mensagem personalizada
String? emailValidator(String? value) {
  return Validators.email(
    value,
    message: 'Por favor, insira um email válido',
  );
}

// Múltiplas validações
String? complexValidator(String? value) {
  return Validators.combine([
    () => Validators.required(value),
    () => Validators.minLength(value, 3),
    () => Validators.maxLength(value, 50),
  ]);
}
```

## 🎭 Masks (`masks.dart`)

Sistema de máscaras para formatação de dados.

### Uso Básico

```dart
import 'package:dreamkeys_corretor_app/shared/utils/masks.dart';

// Aplicar máscara
String cpfFormatado = Masks.cpf('12345678901'); // '123.456.789-01'
String phoneFormatado = Masks.phone('11987654321'); // '(11) 98765-4321'

// Remover máscara
String cpfLimpo = Masks.unmaskCpf('123.456.789-01'); // '12345678901'
```

### Máscaras Disponíveis

- `cpf()` / `unmaskCpf()` - CPF: 000.000.000-00
- `cnpj()` / `unmaskCnpj()` - CNPJ: 00.000.000/0000-00
- `phone()` / `unmaskPhone()` - Telefone: (00) 00000-0000
- `cep()` / `unmaskCep()` - CEP: 00000-000
- `money()` / `unmaskMoney()` - Valor: R$ 0,00
- `percentage()` / `unmaskPercentage()` - Porcentagem: 0,00%
- `date()` / `unmaskDate()` - Data: 00/00/0000
- `time()` / `unmaskTime()` - Hora: 00:00
- `unmaskAll()` - Remove todas as máscaras
- `capitalize()` - Capitaliza primeira letra
- `removeAccents()` - Remove acentos

### Exemplos

```dart
// Formatação em tempo real
TextEditingController controller = TextEditingController();
controller.addListener(() {
  final masked = Masks.cpf(controller.text);
  controller.value = controller.value.copyWith(
    text: masked,
    selection: TextSelection.collapsed(offset: masked.length),
  );
});

// Conversão para backend
String cpfParaAPI = Masks.unmaskCpf(controller.text);
```

## 📝 Input Formatters (`input_formatters.dart`)

Formatters para aplicar máscaras automaticamente em TextFields.

### Uso Básico

```dart
import 'package:dreamkeys_corretor_app/shared/utils/input_formatters.dart';

TextField(
  inputFormatters: [CpfInputFormatter()],
  // ...
)
```

### Formatters Disponíveis

- `CpfInputFormatter()` - CPF
- `CnpjInputFormatter()` - CNPJ
- `PhoneInputFormatter()` - Telefone
- `CepInputFormatter()` - CEP
- `MoneyInputFormatter()` - Valor monetário
- `PercentageInputFormatter()` - Porcentagem
- `DateInputFormatter()` - Data
- `TimeInputFormatter()` - Hora
- `NumericInputFormatter()` - Apenas números
- `LettersOnlyInputFormatter()` - Apenas letras
- `LengthLimitingFormatter(maxLength)` - Limite de caracteres
- `CapitalizeInputFormatter()` - Capitalizar palavras

### Exemplos

```dart
// Campo com CPF
TextFormField(
  controller: cpfController,
  inputFormatters: [CpfInputFormatter()],
  validator: Validators.cpf,
)

// Campo com telefone e validação
TextFormField(
  controller: phoneController,
  inputFormatters: [PhoneInputFormatter()],
  keyboardType: TextInputType.number,
  validator: (value) => Validators.phone(value, required: true),
)

// Múltiplos formatters
TextFormField(
  inputFormatters: [
    CpfInputFormatter(),
    LengthLimitingFormatter(14),
  ],
)
```

## 🧩 MaskedTextField (`masked_text_field.dart`)

Widget completo que combina máscara, formatter e validação.

### Uso

```dart
import 'package:dreamkeys_corretor_app/shared/widgets/masked_text_field.dart';

MaskedTextField(
  label: 'CPF',
  controller: cpfController,
  maskType: MaskType.cpf,
  required: true,
)

MaskedTextField(
  label: 'Telefone',
  controller: phoneController,
  maskType: MaskType.phone,
  prefixIcon: Icon(Icons.phone),
)
```

### Tipos de Máscara

- `MaskType.cpf` - CPF
- `MaskType.cnpj` - CNPJ
- `MaskType.phone` - Telefone
- `MaskType.cep` - CEP
- `MaskType.money` - Valor monetário
- `MaskType.percentage` - Porcentagem
- `MaskType.date` - Data
- `MaskType.time` - Hora
- `MaskType.numeric` - Apenas números
- `MaskType.lettersOnly` - Apenas letras
- `MaskType.none` - Sem máscara

### Exemplos Completos

```dart
// Campo de CPF com validação automática
MaskedTextField(
  label: 'CPF',
  hint: '000.000.000-00',
  controller: cpfController,
  maskType: MaskType.cpf,
  required: true,
  prefixIcon: Icon(Icons.badge_outlined),
)

// Campo de telefone opcional
MaskedTextField(
  label: 'Telefone',
  controller: phoneController,
  maskType: MaskType.phone,
  required: false,
  keyboardType: TextInputType.number,
)

// Campo de valor monetário
MaskedTextField(
  label: 'Valor',
  controller: valueController,
  maskType: MaskType.money,
  required: true,
  prefixIcon: Icon(Icons.attach_money),
)
```

## 🔄 Fluxo Completo

```dart
// 1. Controller
final cpfController = TextEditingController();

// 2. Widget com máscara
MaskedTextField(
  label: 'CPF',
  controller: cpfController,
  maskType: MaskType.cpf,
  required: true,
)

// 3. Ao enviar, remove máscara para API
String cpfLimpo = Masks.unmaskCpf(cpfController.text);

// 4. Validação manual se necessário
String? error = Validators.cpf(cpfLimpo);
```

## 📝 Boas Práticas

1. **Use validators** para validação de dados
2. **Use masks** para formatação de exibição
3. **Use formatters** para aplicar máscaras em tempo real
4. **Use MaskedTextField** para campos comuns
5. **Sempre remova máscaras** antes de enviar para API
6. **Combine validações** quando necessário
7. **Mensagens personalizadas** para melhor UX

## 🔗 Integração com Formulários

```dart
final _formKey = GlobalKey<FormState>();

Form(
  key: _formKey,
  child: Column(
    children: [
      MaskedTextField(
        label: 'CPF',
        controller: cpfController,
        maskType: MaskType.cpf,
        required: true,
      ),
      MaskedTextField(
        label: 'Telefone',
        controller: phoneController,
        maskType: MaskType.phone,
        required: false,
      ),
      ElevatedButton(
        onPressed: () {
          if (_formKey.currentState!.validate()) {
            // Formulário válido
            final cpf = Masks.unmaskCpf(cpfController.text);
            final phone = Masks.unmaskPhone(phoneController.text);
            // Enviar para API...
          }
        },
        child: Text('Enviar'),
      ),
    ],
  ),
)
```

---

**Última atualização**: 2024-01-20
