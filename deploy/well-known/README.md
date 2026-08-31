# Deep links https → app Intellisys

Estes dois arquivos são **infraestrutura de servidor**, não código do app. Sem eles
publicados, o entitlement do iOS e o `intent-filter` do Android **não fazem nada**:
o link continua abrindo no navegador, sem erro em lugar nenhum.

## Domínio

`https://intellisysbr.com` — é o domínio dos links que o backend manda por e-mail
(`FRONTEND_URL` / `APP_URL` no `.env` do imobx = `https://intellisysbr.com/sistema`).
Exemplo de link real: `https://intellisysbr.com/sistema/kanban/task/{id}?teamId={id}`.

Só o apex `intellisysbr.com` está declarado (`applinks:intellisysbr.com` no
entitlement, `android:host="intellisysbr.com"` no manifest). Se os e-mails passarem
a sair com `www.intellisysbr.com`, é preciso declarar **também** esse host nos dois
lugares e servir os arquivos nele — não basta o redirect. (O guard Dart em
`DeepLinkService._appHosts` já aceita as duas formas.)

> **Armadilha:** no Android, um `intent-filter` com `autoVerify="true"` só é dado
> como verificado se **TODOS** os hosts declarados nele verificarem. Acrescentar
> `www.intellisysbr.com` sem servir o `assetlinks.json` nesse host derruba a
> verificação do apex junto — os links param de abrir o app **inteiramente**.
> Por isso o `www` ficou de fora até haver arquivo no ar nele.

> Atenção: os arquivos ficam na **raiz do domínio**, em `/.well-known/` — **não**
> sob `/sistema`. O SPA é servido com base `/sistema`, então se a raiz de
> `intellisysbr.com` for outro host/servidor (landing, proxy, WordPress), é lá que
> os arquivos precisam ser publicados.

## iOS — `apple-app-site-association`

Publicar em:

```
https://intellisysbr.com/.well-known/apple-app-site-association
```

Requisitos (todos obrigatórios, o iOS é rígido):

- **Sem extensão** no nome do arquivo (não é `.json`).
- Servido como `Content-Type: application/json`.
- **HTTPS, sem redirect** (nem de `www` para apex, nem de `http`). Um 301/302 na
  URL do AASA invalida a associação.
- Sem autenticação, resposta `200`.

### TEAM_ID — PREENCHIDO (31/08/2026)

`Z6CR6MJV22.com.dreamkeys.corretor`. O Team ID veio da conta Apple Developer
(cabeçalho da conta: "RAFAEL CORREA - Z6CR6MJV22"). Não existe em nenhum dos
repositórios: o `project.pbxproj` não tem `DEVELOPMENT_TEAM` porque a assinatura
é automática, feita pelo Codemagic.

O bundle id (`com.dreamkeys.corretor`) esse sim está no projeto
(`PRODUCT_BUNDLE_IDENTIFIER` no pbxproj e `applicationId` no `build.gradle.kts`).

### Ainda no portal Apple

Habilitar **Associated Domains** no App ID de `com.dreamkeys.corretor`. Sem isso o
perfil de provisionamento não assina o entitlement e o build quebra.

### Cache

O iOS cacheia o AASA de forma agressiva (via CDN da Apple). Um AASA errado no
momento da primeira instalação pode exigir **reinstalar o app** para testar de novo.
Publique o arquivo **antes** de distribuir o build.

## Android — `assetlinks.json`

Publicar em:

```
https://intellisysbr.com/.well-known/assetlinks.json
```

Mesmas regras: `Content-Type: application/json`, HTTPS, **sem redirect**, `200`.

### SHA-256 — PREENCHIDO (31/08/2026)

`3E:4F:EA:54:...:CB:BA` — o fingerprint da **chave de assinatura do app** (a que
o Google Play usa para re-assinar), **não** o da `upload-keystore.jks`, cujo
SHA-1 é `87:81:13:A0:...`.

Onde ele fica no Play Console (o menu mudou de lugar em 2026 — "Integridade do
app" agora só redireciona para "Protegido com o Google Play"; a chave continua
na rota antiga):

```
https://play.google.com/console/u/0/developers/6173870229946082471/app/4973079925022951476/keymanagement
```

Bloco **"Chave de assinatura do app" (Em uso)** → botão *Impressão digital para
certificação SHA-256*. O bloco de baixo, "Certificado da chave de upload", é o
errado.

Se um dia for testar um build local assinado com a chave de upload, dá para pôr
**os dois** fingerprints no array `sha256_cert_fingerprints`.

### Verificação

`autoVerify="true"` só é verificado **na instalação**. Se o `assetlinks.json`
estiver fora do ar ou errado nesse momento, o link cai no navegador e só volta ao
normal com reinstalação ou com o toggle manual em
*Configurações → Apps → Intellisys → Abrir por padrão → Links*.

Conferência rápida depois de publicar (com o app instalado, via adb):

```
adb shell pm get-app-links com.dreamkeys.corretor
```

Deve aparecer `intellisysbr.com: verified`.

## Como publicar na Hostinger (passo a passo)

O site está na Hostinger atrás da Cloudflare, e o CRM é servido em
`/sistema` (ver `imobx-front/public/.htaccess`). Os arquivos de deep link vão na
**raiz**, não sob `/sistema`.

1. hPanel → **Gerenciador de Arquivos** → abrir `public_html/`.
2. Criar a pasta `.well-known`.
3. Subir os TRÊS arquivos desta pasta para dentro dela:
   - `apple-app-site-association` (sem extensão — se o gerenciador acrescentar
     `.json`, renomear tirando)
   - `assetlinks.json`
   - `.htaccess`
4. Cloudflare → **Caching → Purge** (as duas URLs, ou tudo).
5. Conferir:

```bash
curl -sI https://intellisysbr.com/.well-known/apple-app-site-association
curl -sI https://intellisysbr.com/.well-known/assetlinks.json
```

Os dois precisam responder `200` com `content-type: application/json`.
`301`/`302` (redirect apex→www, por exemplo) **invalida a associação no iOS**.

### Por que o `.htaccess` é obrigatório

O `apple-app-site-association` não tem extensão, então o Apache não descobre o
tipo e serve como texto puro — e o iOS recusa a associação **em silêncio**. O
`ForceType application/json` resolve. A segunda regra do arquivo impede que um
fallback de SPA na raiz devolva `index.html` com status 200 no lugar do JSON —
foi exatamente esse acidente que causou o incidente de MIME em `/sistema` nos
dias 27 e 28/08/2026.

## Recorte de paths — por que não é `/sistema/*`

Os dois arquivos declaram uma **whitelist** dos caminhos que o app sabe abrir
(kanban, agenda, imóveis, clientes, fichas, vistorias, documentos, checklists,
check-in, chat, integrações) e **excluem explicitamente**:

- `/sistema/reset-password/{token}`
- `/sistema/verify-email?token=`
- `/sistema/login`, `/sistema/unsubscribe`, `/sistema/email-preferences`

Se esses caminhos fossem capturados, o usuário clicaria em "redefinir senha" no
e-mail e cairia dentro do app, que **não tem tela para eles** — senha nenhuma
redefinida. É regressão em cima de um fluxo que hoje funciona no navegador.

O Android não suporta exclusão em `intent-filter`, então o `AndroidManifest.xml`
lista os `pathPrefix` um a um pelo mesmo motivo — nunca `/sistema` inteiro.

## Ao mudar a whitelist

A fonte da verdade do roteamento é
`lib/shared/utils/app_deep_link.dart` (`_normalizeMobilePath`). Se um caminho novo
ganhar tela no app, atualize **três** lugares juntos: o `switch` do Dart, os
`pathPrefix` do `AndroidManifest.xml` e as listas `components`/`paths` do AASA.
Caminho declarado aqui e não tratado no Dart abre o app e não navega para lugar
nenhum.
