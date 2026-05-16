# Push notifications — guia de ativação

> **Status do código**: 100% pronto. Toda a infra (Flutter, iOS, Android, backend
> NestJS) já foi escrita e está commitada. Falta apenas ligar as credenciais do
> Firebase / APNs — passos **manuais** que só você consegue executar (precisam
> da sua conta Firebase, da sua Apple Developer Membership e das envs do servidor).
>
> Enquanto este guia não for concluído o app abre normalmente, só não chega push
> remoto: o `AppDelegate` (iOS) e o `AppPushService` (Dart) detectam placeholders
> e silenciam o Firebase.

---

## 1. Criar o projeto Firebase (uma vez por ambiente)

1. Acesse <https://console.firebase.google.com/> e crie um projeto
   (ex.: `intellisys-prod`). Pode reaproveitar um existente.
2. **Adicionar app Android** com package `com.dreamkeys.corretor`. Baixe o
   `google-services.json` real e substitua o arquivo em
   `dreamkeysapp/android/app/google-services.json` (hoje contém placeholders).
3. **Adicionar app iOS** com bundle id `com.dreamkeys.corretor`. Baixe o
   `GoogleService-Info.plist` real e substitua
   `dreamkeysapp/ios/Runner/GoogleService-Info.plist` (hoje placeholder).

> **Importante**: NÃO comite `google-services.json` / `GoogleService-Info.plist`
> em repositório público. Para repositório privado, está OK.

---

## 2. Gerar `firebase_options.dart` (Flutter)

No Mac/Linux com a CLI do FlutterFire:

```bash
dart pub global activate flutterfire_cli
cd dreamkeysapp
flutterfire configure --project=<seu-project-id-firebase>
```

Isso atualiza `dreamkeysapp/lib/firebase_options.dart` com os valores reais.
A partir desse momento `DefaultFirebaseOptions.isFirebaseConfigured == true`
e o `AppPushService` passa a inicializar Firebase em background/foreground.

> Se rodar em Windows: o flutterfire CLI também funciona, basta ter o
> `firebase-tools` (`npm i -g firebase-tools`) e estar logado (`firebase login`).

---

## 3. iOS · APNs Auth Key (uma vez por conta Apple Developer)

Sem esta chave o Firebase **não consegue entregar push em iPhone**.

1. <https://developer.apple.com/account/resources/authkeys/list>
2. **Keys → +** → marque **Apple Push Notifications service (APNs)** → Continue → Register.
3. Baixe o arquivo `.p8` (download único). Guarde em local seguro.
4. Copie o **Key ID** (10 caracteres) e o **Team ID** (canto superior direito da
   conta Apple Developer).
5. No Firebase Console → **Project settings** → aba **Cloud Messaging** →
   secção **Apple app configuration** → **Upload** o `.p8`, com Key ID e Team ID.

A partir daqui o iOS deve receber notificações pelo APNs do Firebase.

---

## 4. iOS · Capability "Push Notifications" no provisioning profile

1. Apple Developer → **Identifiers** → seu App ID `com.dreamkeys.corretor` →
   **Edit** → marque **Push Notifications** → Save.
2. Regenere o profile de Distribution e Development com a capability ativa
   (Xcode → Signing & Capabilities → Automatic costuma fazer isso sozinho).
3. No Xcode, abrindo o `dreamkeysapp/ios/Runner.xcworkspace`, a aba
   **Signing & Capabilities** já vai mostrar **Push Notifications** habilitado
   (já gravamos no `project.pbxproj`).

---

## 5. Backend · service account FCM

O `MobilePushService` (`imobx/src/notifications/mobile-push.service.ts`) só
dispara quando recebe credencial via env. Sem ela o serviço inicializa em modo
"desligado" e nada é enviado.

1. Firebase Console → **Project settings** → aba **Service accounts** →
   **Generate new private key** (botão azul). Baixa um JSON.
2. **Cole o conteúdo desse JSON em uma única linha** na env do backend,
   escapando aspas duplas. Em `.env`:

```env
FIREBASE_SERVICE_ACCOUNT_JSON={"type":"service_account","project_id":"...","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...","client_id":"...","auth_uri":"...","token_uri":"...","auth_provider_x509_cert_url":"...","client_x509_cert_url":"..."}
```

> Em produção (Render / Railway / EC2 / etc), configure a env do mesmo jeito.
> Restart o backend. No log você vai ver:
> `[MobilePushService] Firebase Admin inicializado — FCM ativo.`

A migration `CreateUserPushTokensTable` já existe; rode `pnpm migration:run`
caso ainda não tenha rodado nesse banco.

---

## 6. Testar

1. Faça login no app em um celular físico (emulador iOS **não** recebe push;
   emulador Android moderno via Play Services recebe).
2. Em fluxos que geram notificação no sistema (lead distribuído, tarefa criada,
   proposta finalizada, etc) o backend chama `notificationService.create(...)`,
   que automaticamente dispara `mobilePushService.sendForNotification(saved)`.
3. Verifique o log do backend — sucesso aparece sem warnings; erros tipo
   `messaging/invalid-registration-token` são tratados (token inválido é
   removido da tabela `user_push_tokens`).
4. Para testar manualmente um push isolado, no Firebase Console → **Cloud
   Messaging** → **Send test message** com o token FCM mostrado no debug do
   app (`📱 [PUSH] FCM token (prefixo): xxxx…`).

---

## 7. Arquivos relevantes

| Lugar | O quê |
| --- | --- |
| `dreamkeysapp/lib/core/push/app_push_service.dart` | cliente FCM + notificações locais |
| `dreamkeysapp/lib/firebase_options.dart` | gerado pelo `flutterfire configure` |
| `dreamkeysapp/ios/Runner/AppDelegate.swift` | bootstrap nativo do Firebase |
| `dreamkeysapp/ios/Runner/Runner.entitlements` | `aps-environment` (interpolado por config) |
| `dreamkeysapp/ios/Runner/GoogleService-Info.plist` | substituir pelo real |
| `dreamkeysapp/android/app/google-services.json` | substituir pelo real |
| `imobx/src/notifications/mobile-push.service.ts` | envio via Firebase Admin |
| `imobx/src/entities/user-push-token.entity.ts` | tokens dos dispositivos |
| `imobx/src/migrations/20605040000000-CreateUserPushTokensTable.ts` | migration |

---

## Resumo do fluxo

```
NotificationService.create(...)
        │
        ├─► WebSocket (in-app, real-time)
        │
        └─► MobilePushService.sendForNotification(saved)
                │
                ├─► busca tokens em user_push_tokens (por userId)
                ├─► admin.messaging().sendEachForMulticast({ tokens, notification, data })
                │     • Android: channelId=imobx_alerts (heads-up + som)
                │     • iOS: aps.sound=default, badge=1
                ├─► remove tokens inválidos do banco
                │
                └─► Firebase → APNs (iOS) / GCM (Android)
                                        │
                                        ▼
                                  Celular do usuário
                                  (igual WhatsApp/Insta)
```
