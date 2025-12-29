# 📋 API de Perfil do Usuário - Documentação Revisada

## Visão Geral

Este documento descreve todos os endpoints relacionados ao perfil do usuário autenticado. Todos os endpoints requerem autenticação via token Bearer.

## 🔐 Autenticação

**TODOS os endpoints desta seção requerem autenticação:**

```http
Authorization: Bearer <access_token>
```

⚠️ **IMPORTANTE:** Use o formato `Bearer <token>` (com espaço após "Bearer").

---

## 📡 Endpoints

### 1. Obter Perfil do Usuário

**Endpoint:** `GET /auth/profile`

**Descrição:** Retorna os dados completos do perfil do usuário autenticado.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Response de Sucesso (200 OK):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
  "name": "João Silva",
  "email": "joao.silva@exemplo.com",
  "phone": "+5511999999999",
  "cellphone": "+5511888888888",
  "avatar": "https://cdn.exemplo.com/avatars/user-123.jpg",
  "role": "user",
  "companyId": "company-uuid-123",
  "companyName": "Imobiliária Exemplo",
  "isAvailableForPublicSite": true,
  "preferences": {
    "notifications": {
      "email": true,
      "push": true,
      "sms": false
    },
    "language": "pt-BR",
    "timezone": "America/Sao_Paulo"
  },
  "tagIds": ["tag-1", "tag-2", "tag-3"],
  "createdAt": "2023-09-20T15:30:00.000Z",
  "updatedAt": "2024-01-15T10:20:00.000Z"
}
```

**Campos da Response:**

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | string | ID único do usuário |
| `name` | string | Nome completo do usuário |
| `email` | string | Email do usuário |
| `phone` | string \| null | Telefone fixo (opcional) |
| `cellphone` | string \| null | Telefone celular (opcional) |
| `avatar` | string \| null | URL do avatar do usuário (opcional) |
| `role` | string | Role do usuário (user, admin, manager, master) |
| `companyId` | string | ID da empresa do usuário |
| `companyName` | string \| null | Nome da empresa (opcional) |
| `isAvailableForPublicSite` | boolean | Se o perfil aparece no site público |
| `preferences` | object | Preferências do usuário |
| `preferences.notifications` | object | Preferências de notificações |
| `preferences.language` | string | Idioma preferido (padrão: "pt-BR") |
| `preferences.timezone` | string | Timezone (padrão: "America/Sao_Paulo") |
| `tagIds` | string[] \| null | IDs das tags associadas ao perfil |
| `createdAt` | string | Data de criação (ISO 8601) |
| `updatedAt` | string | Data da última atualização (ISO 8601) |

**Erros:**

- **401 Unauthorized:** Token inválido ou expirado
- **404 Not Found:** Usuário não encontrado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript (Axios)
const getProfile = async () => {
  const response = await apiClient.get('/auth/profile', {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
  return response.data;
};
```

```dart
// Flutter/Dart
Future<Profile> getProfile() async {
  final response = await authenticatedRequest('GET', '/auth/profile');
  if (response.statusCode == 200) {
    return Profile.fromJson(json.decode(response.body));
  }
  throw Exception('Erro ao buscar perfil');
}
```

---

### 2. Atualizar Perfil do Usuário

**Endpoint:** `PATCH /auth/profile`

**Descrição:** Atualiza os dados do perfil do usuário autenticado.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "name": "João Silva Santos",
  "phone": "+5511999999999",
  "cellphone": "+5511888888888",
  "tagIds": ["tag-1", "tag-2", "tag-3"]
}
```

**Campos do Request:**

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|------------|-----------|
| `name` | string | Não | Nome completo do usuário |
| `phone` | string | Não | Telefone fixo |
| `cellphone` | string | Não | Telefone celular |
| `tagIds` | string[] | Não | Array de IDs das tags |

**Response de Sucesso (200 OK):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
  "name": "João Silva Santos",
  "email": "joao.silva@exemplo.com",
  "phone": "+5511999999999",
  "cellphone": "+5511888888888",
  "avatar": "https://cdn.exemplo.com/avatars/user-123.jpg",
  "role": "user",
  "companyId": "company-uuid-123",
  "companyName": "Imobiliária Exemplo",
  "isAvailableForPublicSite": true,
  "preferences": { ... },
  "tagIds": ["tag-1", "tag-2", "tag-3"],
  "createdAt": "2023-09-20T15:30:00.000Z",
  "updatedAt": "2024-01-15T10:25:00.000Z"
}
```

**Erros:**

- **400 Bad Request:** Dados inválidos
- **401 Unauthorized:** Token inválido ou expirado
- **404 Not Found:** Usuário não encontrado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript
const updateProfile = async (data: {
  name?: string;
  phone?: string;
  cellphone?: string;
  tagIds?: string[];
}) => {
  const response = await apiClient.patch('/auth/profile', data, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
  });
  return response.data;
};
```

```dart
// Flutter/Dart
Future<Profile> updateProfile({
  String? name,
  String? phone,
  String? cellphone,
  List<String>? tagIds,
}) async {
  final body = <String, dynamic>{};
  if (name != null) body['name'] = name;
  if (phone != null) body['phone'] = phone;
  if (cellphone != null) body['cellphone'] = cellphone;
  if (tagIds != null) body['tagIds'] = tagIds;

  final response = await authenticatedRequest(
    'PATCH',
    '/auth/profile',
    body: body,
  );

  if (response.statusCode == 200) {
    return Profile.fromJson(json.decode(response.body));
  }
  throw Exception('Erro ao atualizar perfil');
}
```

---

### 3. Upload de Avatar

**Endpoint:** `POST /auth/avatar`

**Descrição:** Faz upload de uma imagem como avatar do usuário.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: multipart/form-data
```

**Request Body (Form Data):**
```
avatar: <arquivo de imagem>
```

**Tipos de arquivo aceitos:**
- `image/jpeg`
- `image/png`
- `image/webp`

**Tamanho máximo:** 5MB

**Response de Sucesso (200 OK):**
```json
{
  "avatar": "https://cdn.exemplo.com/avatars/user-123-abc123.jpg",
  "message": "Avatar atualizado com sucesso"
}
```

**Erros:**

- **400 Bad Request:** Arquivo inválido ou muito grande
- **401 Unauthorized:** Token inválido ou expirado
- **415 Unsupported Media Type:** Tipo de arquivo não suportado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript (Axios)
const uploadAvatar = async (file: File) => {
  const formData = new FormData();
  formData.append('avatar', file);

  const response = await apiClient.post('/auth/avatar', formData, {
    headers: {
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'multipart/form-data',
    },
  });
  return response.data;
};
```

```dart
// Flutter/Dart
Future<String> uploadAvatar(File imageFile) async {
  final token = await storage.read(key: 'access_token');
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/auth/avatar'),
  );

  request.headers['Authorization'] = 'Bearer $token';
  request.files.add(
    await http.MultipartFile.fromPath('avatar', imageFile.path),
  );

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['avatar'] as String;
  }
  throw Exception('Erro ao fazer upload do avatar');
}
```

---

### 4. Remover Avatar

**Endpoint:** `DELETE /auth/profile`

**Descrição:** Remove o avatar do usuário, deixando-o como `null`.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "avatar": null
}
```

**Response de Sucesso (200 OK):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-1234-567890abcdef",
  "name": "João Silva",
  "email": "joao.silva@exemplo.com",
  "avatar": null,
  ...
}
```

**Erros:**

- **401 Unauthorized:** Token inválido ou expirado
- **404 Not Found:** Usuário não encontrado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript
const removeAvatar = async () => {
  const response = await apiClient.delete('/auth/profile', {
    headers: {
      Authorization: `Bearer ${accessToken}`,
    },
    data: {
      avatar: null,
    },
  });
  return response.data;
};
```

```dart
// Flutter/Dart
Future<Profile> removeAvatar() async {
  final response = await authenticatedRequest(
    'DELETE',
    '/auth/profile',
    body: {'avatar': null},
  );

  if (response.statusCode == 200) {
    return Profile.fromJson(json.decode(response.body));
  }
  throw Exception('Erro ao remover avatar');
}
```

---

### 5. Atualizar Visibilidade Pública

**Endpoint:** `PATCH /auth/profile/public-visibility`

**Descrição:** Atualiza se o perfil do usuário aparece no site público.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "isAvailableForPublicSite": true
}
```

**Campos do Request:**

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|------------|-----------|
| `isAvailableForPublicSite` | boolean | Sim | Se o perfil aparece no site público |

**Response de Sucesso (200 OK):**
```json
{
  "isAvailableForPublicSite": true,
  "message": "Visibilidade pública atualizada com sucesso"
}
```

**Erros:**

- **400 Bad Request:** Dados inválidos
- **401 Unauthorized:** Token inválido ou expirado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript
const updatePublicVisibility = async (isVisible: boolean) => {
  const response = await apiClient.patch(
    '/auth/profile/public-visibility',
    { isAvailableForPublicSite: isVisible },
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    }
  );
  return response.data;
};
```

```dart
// Flutter/Dart
Future<bool> updatePublicVisibility(bool isVisible) async {
  final response = await authenticatedRequest(
    'PATCH',
    '/auth/profile/public-visibility',
    body: {'isAvailableForPublicSite': isVisible},
  );

  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['isAvailableForPublicSite'] as bool;
  }
  throw Exception('Erro ao atualizar visibilidade');
}
```

---

### 6. Alterar Senha

**Endpoint:** `POST /auth/change-password`

**Descrição:** Altera a senha do usuário autenticado.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Request Body:**
```json
{
  "currentPassword": "senhaAtual123",
  "newPassword": "novaSenha456",
  "confirmPassword": "novaSenha456"
}
```

**Campos do Request:**

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|------------|-----------|
| `currentPassword` | string | Sim | Senha atual do usuário |
| `newPassword` | string | Sim | Nova senha (mínimo 8 caracteres) |
| `confirmPassword` | string | Sim | Confirmação da nova senha |

**Validações:**
- `newPassword` deve ter no mínimo 8 caracteres
- `newPassword` deve ser igual a `confirmPassword`
- `currentPassword` deve estar correto

**Response de Sucesso (200 OK):**
```json
{
  "message": "Senha alterada com sucesso"
}
```

**Erros:**

- **400 Bad Request:** 
  - Senha atual incorreta
  - Nova senha não atende aos requisitos
  - Senhas não coincidem
- **401 Unauthorized:** Token inválido ou expirado

**Exemplo de Uso:**

```typescript
// JavaScript/TypeScript
const changePassword = async (
  currentPassword: string,
  newPassword: string,
  confirmPassword: string
) => {
  const response = await apiClient.post(
    '/auth/change-password',
    {
      currentPassword,
      newPassword,
      confirmPassword,
    },
    {
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    }
  );
  return response.data;
};
```

```dart
// Flutter/Dart
Future<void> changePassword({
  required String currentPassword,
  required String newPassword,
  required String confirmPassword,
}) async {
  final response = await authenticatedRequest(
    'POST',
    '/auth/change-password',
    body: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    },
  );

  if (response.statusCode != 200) {
    throw Exception('Erro ao alterar senha');
  }
}
```

---

### 7. Listar Sessões Ativas

**Endpoint:** `GET /auth/profile/sessions`

**Descrição:** Retorna todas as sessões ativas do usuário autenticado.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Response de Sucesso (200 OK):**
```json
[
  {
    "id": "session-123",
    "device": "iPhone 13",
    "browser": "Safari",
    "ip": "192.168.1.100",
    "location": "São Paulo, SP",
    "lastActivity": "2024-01-15T10:30:00.000Z",
    "isCurrent": true,
    "createdAt": "2024-01-10T08:00:00.000Z"
  },
  {
    "id": "session-456",
    "device": "Windows PC",
    "browser": "Chrome",
    "ip": "192.168.1.101",
    "location": "Rio de Janeiro, RJ",
    "lastActivity": "2024-01-14T15:20:00.000Z",
    "isCurrent": false,
    "createdAt": "2024-01-05T12:00:00.000Z"
  }
]
```

**Campos da Response:**

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `id` | string | ID da sessão |
| `device` | string | Dispositivo usado |
| `browser` | string | Navegador usado |
| `ip` | string | Endereço IP |
| `location` | string | Localização aproximada |
| `lastActivity` | string | Última atividade (ISO 8601) |
| `isCurrent` | boolean | Se é a sessão atual |
| `createdAt` | string | Data de criação (ISO 8601) |

**Erros:**

- **401 Unauthorized:** Token inválido ou expirado

---

### 8. Encerrar Sessão Específica

**Endpoint:** `DELETE /auth/profile/sessions/:sessionId`

**Descrição:** Encerra uma sessão específica do usuário.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Parâmetros da URL:**

| Parâmetro | Tipo | Descrição |
|-----------|------|-----------|
| `sessionId` | string | ID da sessão a ser encerrada |

**Response de Sucesso (200 OK):**
```json
{
  "message": "Sessão encerrada com sucesso"
}
```

**Erros:**

- **401 Unauthorized:** Token inválido ou expirado
- **404 Not Found:** Sessão não encontrada

---

### 9. Encerrar Todas as Outras Sessões

**Endpoint:** `DELETE /auth/profile/sessions/others`

**Descrição:** Encerra todas as sessões do usuário, exceto a sessão atual.

**Headers:**
```http
Authorization: Bearer <access_token>
Content-Type: application/json
```

**Response de Sucesso (200 OK):**
```json
{
  "message": "Todas as outras sessões foram encerradas",
  "sessionsEnded": 3
}
```

**Erros:**

- **401 Unauthorized:** Token inválido ou expirado

---

## 🚨 Tratamento de Erros Comuns

### Erro 401 - Unauthorized

```json
{
  "message": "Unauthorized",
  "errorCode": "UNAUTHORIZED",
  "details": {
    "reason": "Token de autenticação inválido ou ausente",
    "suggestion": "Verifique se o token está correto e não expirou"
  }
}
```

**Ações:**
1. Verificar se o header `Authorization` está sendo enviado
2. Verificar se o formato está correto: `Bearer <token>`
3. Verificar se o token não expirou
4. Se o token expirou, fazer refresh ou redirecionar para login

### Erro 400 - Bad Request

```json
{
  "message": "Dados inválidos",
  "errorCode": "VALIDATION_ERROR",
  "details": {
    "field": "newPassword",
    "reason": "A senha deve ter no mínimo 8 caracteres"
  }
}
```

**Ações:**
1. Verificar os dados enviados
2. Verificar as validações de cada campo
3. Corrigir os dados e tentar novamente

### Erro 404 - Not Found

```json
{
  "message": "Recurso não encontrado",
  "errorCode": "NOT_FOUND"
}
```

**Ações:**
1. Verificar se o endpoint está correto
2. Verificar se o ID do recurso existe
3. Verificar se o usuário tem permissão para acessar o recurso

---

## 📋 Checklist de Implementação

- [ ] Endpoint `GET /auth/profile` implementado
- [ ] Endpoint `PATCH /auth/profile` implementado
- [ ] Endpoint `POST /auth/avatar` implementado
- [ ] Endpoint `DELETE /auth/profile` (remover avatar) implementado
- [ ] Endpoint `PATCH /auth/profile/public-visibility` implementado
- [ ] Endpoint `POST /auth/change-password` implementado
- [ ] Endpoint `GET /auth/profile/sessions` implementado
- [ ] Endpoint `DELETE /auth/profile/sessions/:id` implementado
- [ ] Endpoint `DELETE /auth/profile/sessions/others` implementado
- [ ] Header `Authorization: Bearer <token>` sendo enviado em todas as requisições
- [ ] Tratamento de erro 401 implementado
- [ ] Tratamento de erro 400 implementado
- [ ] Tratamento de erro 404 implementado
- [ ] Validação de dados no front-end antes de enviar

---

## 🔍 Debugging

### Verificar se o token está sendo enviado

**No navegador (DevTools):**
1. Abra a aba Network
2. Faça uma requisição
3. Clique na requisição
4. Vá em "Headers"
5. Procure por "Request Headers" → "Authorization"
6. Deve aparecer: `Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...`

**No Flutter:**
```dart
print('Token: $token');
print('Header: Bearer $token');
```

### Verificar resposta da API

**No navegador (DevTools):**
1. Abra a aba Network
2. Faça uma requisição
3. Clique na requisição
4. Vá em "Response"
5. Verifique o JSON retornado

**No Flutter:**
```dart
print('Status Code: ${response.statusCode}');
print('Response Body: ${response.body}');
```

---

## 📚 Resumo dos Endpoints

| Método | Endpoint | Descrição |
|--------|----------|-----------|
| `GET` | `/auth/profile` | Obter perfil do usuário |
| `PATCH` | `/auth/profile` | Atualizar perfil do usuário |
| `POST` | `/auth/avatar` | Upload de avatar |
| `DELETE` | `/auth/profile` | Remover avatar |
| `PATCH` | `/auth/profile/public-visibility` | Atualizar visibilidade pública |
| `POST` | `/auth/change-password` | Alterar senha |
| `GET` | `/auth/profile/sessions` | Listar sessões ativas |
| `DELETE` | `/auth/profile/sessions/:id` | Encerrar sessão específica |
| `DELETE` | `/auth/profile/sessions/others` | Encerrar outras sessões |

---

## ⚡ Dicas de Performance

1. **Cache do perfil:** Após obter o perfil, armazene-o localmente e use-o ao invés de fazer requisições desnecessárias
2. **Atualização otimista:** Atualize a UI imediatamente e faça a requisição em background
3. **Validação no front-end:** Valide os dados antes de enviar para evitar requisições desnecessárias
4. **Debounce em campos de busca:** Se houver busca de tags, use debounce para evitar muitas requisições

---

## 📞 Suporte

Em caso de dúvidas ou problemas, verifique:
1. Se o formato do header está correto: `Bearer <token>`
2. Se o token está sendo enviado
3. Se o token não expirou
4. Os logs do servidor para mais detalhes



