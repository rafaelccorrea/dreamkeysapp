# 📁 Estrutura do Projeto - Dream Keys

## 🎯 Visão Geral

Este documento descreve a estrutura organizacional do projeto Flutter, focada em reutilização de código, separação de responsabilidades e escalabilidade.

## 📂 Estrutura de Pastas

```
lib/
├── core/                    # Configurações e funcionalidades centrais
│   ├── constants/          # Constantes da aplicação
│   │   └── api_constants.dart
│   └── theme/              # Temas e cores
│       ├── app_colors.dart
│       └── app_theme.dart
│
├── features/               # Funcionalidades organizadas por feature
│   └── auth/              # Módulo de autenticação
│       └── login/         # Funcionalidade de login
│           └── pages/
│               └── login_page.dart
│
├── shared/                 # Código compartilhado entre features
│   ├── services/          # Serviços de API e lógica de negócio
│   │   ├── api_service.dart
│   │   └── auth_service.dart
│   └── widgets/           # Widgets reutilizáveis
│       ├── custom_button.dart
│       └── custom_text_field.dart
│
└── main.dart              # Ponto de entrada da aplicação
```

## 📋 Descrição dos Diretórios

### `/core`
Contém funcionalidades centrais e configurações base do aplicativo.

- **`constants/`**: Constantes globais como URLs da API, endpoints, etc.
- **`theme/`**: Definição de temas (Light/Dark), paleta de cores, estilos globais.

### `/features`
Organização por funcionalidades do negócio. Cada feature contém:
- Suas próprias páginas/telas
- Controladores/especialistas
- Modelos específicos da feature
- Widgets específicos da feature

**Estrutura de uma Feature:**
```
feature_name/
├── pages/          # Telas da feature
├── widgets/        # Widgets específicos da feature
├── models/         # Modelos de dados
├── controllers/    # Lógica de negócio (se usar GetX, Provider, etc.)
└── services/       # Serviços específicos da feature (se necessário)
```

### `/shared`
Código compartilhado entre múltiplas features:

- **`services/`**: Serviços de API, autenticação, storage, etc.
- **`widgets/`**: Componentes UI reutilizáveis (botões, inputs, cards, etc.)
- **`utils/`**: Utilitários e helpers (formatação, validação, etc.)
- **`models/`**: Modelos de dados compartilhados

## 🎨 Sistema de Cores

As cores estão centralizadas em `lib/core/theme/app_colors.dart` e suportam:
- **Light Mode**: Cores otimizadas para tema claro
- **Dark Mode**: Cores otimizadas para tema escuro

**Uso:**
```dart
import 'package:dreamkeys_app/core/theme/app_colors.dart';

// Acessar cores
AppColors.primary.primary          // Cor primária
AppColors.status.success           // Cor de sucesso
AppColors.message.errorText        // Texto de erro
```

## 🔌 Serviços de API

### ApiService
Serviço base para todas as chamadas HTTP. Gerencia:
- Headers automáticos
- Autenticação (Bearer Token)
- Tratamento de erros padronizado
- Timeouts

### AuthService
Serviço específico para autenticação:
- Login
- Logout
- Verificação 2FA
- Recuperação de senha
- Refresh token

## 🧩 Widgets Reutilizáveis

### CustomTextField
Campo de texto customizado com:
- Validação integrada
- Suporte a ícones (prefix/suffix)
- Modo de senha com toggle
- Estilos consistentes com o tema

### CustomButton
Botão customizado com variantes:
- `ButtonVariant.primary`: Botão primário (elevated)
- `ButtonVariant.secondary`: Botão secundário (outlined)
- `ButtonVariant.text`: Botão de texto

## 📱 Páginas

### LoginPage
Tela de login com:
- Validação de formulário
- Integração com AuthService
- Tratamento de erros
- Suporte a "Lembrar-me"
- Link para recuperação de senha

## 🚀 Próximos Passos

1. **Navegação**: Implementar sistema de roteamento
2. **Estado Global**: Implementar gerenciamento de estado (Provider, GetX, ou Riverpod)
3. **Storage**: Implementar armazenamento local (SharedPreferences, Hive, etc.)
4. **Tratamento de Erros**: Sistema global de tratamento de erros
5. **Loading States**: Indicadores de carregamento globais
6. **Validações**: Biblioteca de validações reutilizáveis
7. **2FA**: Tela de verificação de dois fatores
8. **Dashboard**: Tela principal após login

## 📝 Convenções

### Nomenclatura
- **Páginas**: `*_page.dart` (ex: `login_page.dart`)
- **Widgets**: `*_widget.dart` ou descritivo (ex: `custom_button.dart`)
- **Serviços**: `*_service.dart` (ex: `auth_service.dart`)
- **Modelos**: `*_model.dart` ou nome da entidade (ex: `user.dart`)
- **Constantes**: `*_constants.dart` (ex: `api_constants.dart`)

### Imports
Seguir ordem:
1. Imports do Flutter
2. Imports de pacotes externos
3. Imports do projeto (core, shared)
4. Imports relativos (mesma feature)

### Comentários
- Usar `///` para documentação de classes e métodos públicos
- Comentários inline `//` para explicações contextuais

## 🔗 Links Úteis

- [Documentação da API](./APP_CORRETOR_FEATURES.md)
- [Paleta de Cores](./APP_CORRETOR_COLORS.md)
- [Guia de Contribuição](./CONTRIBUTING.md)

---

**Última atualização**: 2024-01-20






