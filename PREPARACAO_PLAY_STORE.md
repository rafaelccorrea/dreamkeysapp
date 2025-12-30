# 📱 Guia de Preparação para Play Store

## ✅ Checklist de Preparação

### 1. Versão do App
- ✅ Versão atual: `1.0.0+1` (definida no `pubspec.yaml`)
- A versão segue o padrão: `MAJOR.MINOR.PATCH+BUILD_NUMBER`
- Para atualizar: edite `pubspec.yaml` linha 5

### 2. Assinatura de Release (Obrigatório)

#### Passo 1: Criar Keystore
```bash
keytool -genkey -v -keystore android/keystore/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

**Importante:** Guarde as senhas e informações em local seguro!

#### Passo 2: Criar arquivo key.properties
Crie o arquivo `android/key.properties` com o seguinte conteúdo:
```properties
storePassword=sua_senha_do_keystore
keyPassword=sua_senha_da_chave
keyAlias=upload
storeFile=../keystore/upload-keystore.jks
```

**⚠️ ATENÇÃO:** 
- NUNCA commite o arquivo `key.properties` ou o keystore no Git!
- Adicione ao `.gitignore`:
  ```
  android/key.properties
  android/keystore/
  *.jks
  *.keystore
  ```

### 3. Build de Release

#### Gerar APK de Release
```bash
flutter build apk --release
```

#### Gerar App Bundle (Recomendado para Play Store)
```bash
flutter build appbundle --release
```

O arquivo gerado estará em: `build/app/outputs/bundle/release/app-release.aab`

### 4. Verificações Finais

#### ✅ AndroidManifest.xml
- [x] Permissões configuradas corretamente
- [x] Backup rules configuradas
- [x] Data extraction rules configuradas
- [x] Label do app: "Dream Keys"
- [x] Application ID: `com.dreamkeys.corretor`

#### ✅ Build Configuration
- [x] ProGuard configurado
- [x] Minificação habilitada
- [x] Shrink resources habilitado
- [x] Assinatura de release configurada

#### ✅ Assets
- [x] Ícones do app presentes em todas as densidades
- [x] Splash screen configurado

### 5. Testes Obrigatórios

Antes de publicar, teste:

1. **Build de Release**
   ```bash
   flutter build apk --release
   flutter install --release
   ```

2. **Funcionalidades Críticas**
   - [ ] Login/Autenticação
   - [ ] Navegação entre telas
   - [ ] Upload de imagens
   - [ ] Chat em tempo real
   - [ ] Notificações (se aplicável)
   - [ ] Biometria (se aplicável)

3. **Performance**
   - [ ] App não trava
   - [ ] Tempo de inicialização aceitável
   - [ ] Uso de memória razoável

4. **Compatibilidade**
   - [ ] Testar em diferentes versões do Android
   - [ ] Testar em diferentes tamanhos de tela

### 6. Informações para Play Store

#### Informações Básicas
- **Nome do App:** Dream Keys
- **Package Name:** com.dreamkeys.corretor
- **Categoria:** Negócios / Imobiliário
- **Classificação de Conteúdo:** Todos

#### Descrição Curta (80 caracteres)
```
Sistema imobiliário completo para corretores
```

#### Descrição Completa
```
Dream Keys - Sistema Imobiliário

Sistema completo de gestão imobiliária desenvolvido para corretores e imobiliárias.

Funcionalidades:
• Gestão de clientes e propriedades
• Sistema de tarefas e projetos (Kanban)
• Chat em tempo real
• Gestão de documentos
• Calendário de eventos
• E muito mais!

Desenvolvido para facilitar o dia a dia dos profissionais do mercado imobiliário.
```

#### Screenshots Necessários
- Pelo menos 2 screenshots obrigatórios
- Recomendado: 4-8 screenshots
- Resoluções:
  - Phone: 1080 x 1920 px (mínimo)
  - Tablet: 1200 x 1920 px (opcional)

#### Ícone do App
- Tamanho: 512 x 512 px
- Formato: PNG (sem transparência)
- Deve estar em: `android/app/src/main/res/mipmap-*/ic_launcher.png`

### 7. Política de Privacidade

A Play Store exige uma política de privacidade se o app:
- Coleta dados pessoais
- Usa câmera/galeria
- Usa localização
- Faz login/autenticação

Crie uma página web com a política de privacidade e adicione o link no Play Console.

### 8. Comandos Úteis

```bash
# Limpar build anterior
flutter clean

# Verificar dependências
flutter pub get

# Analisar código
flutter analyze

# Build APK
flutter build apk --release

# Build App Bundle (recomendado)
flutter build appbundle --release

# Verificar tamanho do APK
flutter build apk --release --split-per-abi
```

### 9. Próximos Passos

1. ✅ Criar keystore
2. ✅ Criar key.properties
3. ✅ Testar build de release
4. ✅ Testar app instalado
5. ⏳ Criar conta no Google Play Console
6. ⏳ Preencher informações do app
7. ⏳ Fazer upload do AAB
8. ⏳ Adicionar screenshots
9. ⏳ Configurar política de privacidade
10. ⏳ Enviar para revisão

### 10. Troubleshooting

#### Erro: "key.properties not found"
- Certifique-se de que o arquivo existe em `android/key.properties`
- Verifique se o caminho do keystore está correto

#### Erro: "Keystore file not found"
- Verifique se o arquivo `.jks` existe no caminho especificado
- Crie a pasta `android/keystore/` se não existir

#### App muito grande
- Use `flutter build appbundle` ao invés de APK
- O App Bundle é otimizado pela Play Store
- Considere usar `--split-per-abi` para APKs menores

---

**Última atualização:** Dezembro 2024

