import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../services/document_service.dart';
import '../models/upload_token_model.dart';
import 'entity_selector.dart';
import '../../clients/services/client_service.dart';

/// Modal para gerenciar links públicos de upload (Upload Tokens)
class UploadTokensModal extends StatefulWidget {
  const UploadTokensModal({super.key});

  @override
  State<UploadTokensModal> createState() => _UploadTokensModalState();
}

class _UploadTokensModalState extends State<UploadTokensModal> {
  final DocumentService _documentService = DocumentService.instance;
  final ClientService _clientService = ClientService.instance;
  
  List<UploadToken> _tokens = [];
  bool _isLoading = true;
  bool _isCreating = false;
  
  // Formulário de criação
  String? _selectedClientId;
  String? _selectedClientName;
  int _expirationDays = 3;
  final TextEditingController _notesController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Não há rota para listar tokens, então começamos com lista vazia
    setState(() {
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // Método removido - não há rota na API para listar tokens

  Future<void> _createToken() async {
    debugPrint('🔗 [UPLOAD_TOKENS_MODAL] _createToken - Iniciando criação de token');
    debugPrint('   - _selectedClientId: $_selectedClientId');
    debugPrint('   - _selectedClientName: $_selectedClientName');
    debugPrint('   - _expirationDays: $_expirationDays');
    
    if (!_formKey.currentState!.validate()) {
      debugPrint('❌ [UPLOAD_TOKENS_MODAL] Validação do formulário falhou');
      return;
    }
    
    if (_selectedClientId == null) {
      debugPrint('❌ [UPLOAD_TOKENS_MODAL] Cliente não selecionado');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Selecione um cliente'),
          backgroundColor: AppColors.status.error,
        ),
      );
      return;
    }

    setState(() {
      _isCreating = true;
    });

    try {
      // Validar clientId antes de enviar
      final clientId = _selectedClientId?.trim();
      debugPrint('🔗 [UPLOAD_TOKENS_MODAL] clientId após trim: "$clientId"');
      
      if (clientId == null || clientId.isEmpty) {
        debugPrint('❌ [UPLOAD_TOKENS_MODAL] clientId está vazio após validação');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Selecione um cliente válido'),
            backgroundColor: AppColors.status.error,
          ),
        );
        setState(() {
          _isCreating = false;
        });
        return;
      }

      debugPrint('🔗 [UPLOAD_TOKENS_MODAL] Chamando createUploadToken com:');
      debugPrint('   - clientId: $clientId');
      debugPrint('   - expirationDays: $_expirationDays');
      
      final response = await _documentService.createUploadToken(
        clientId: clientId,
        expirationDays: _expirationDays,
        notes: _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
      );

      if (mounted) {
        if (response.success && response.data != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Link público criado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          
          // Adicionar o token criado diretamente na lista
          setState(() {
            _tokens.insert(0, response.data!); // Adiciona no início da lista
            _selectedClientId = null;
            _selectedClientName = null;
            _expirationDays = 3;
            _isCreating = false;
          });
          _notesController.clear();
          _formKey.currentState?.reset();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao criar link público'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao criar link: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _copyLink(UploadToken token) async {
    await Clipboard.setData(ClipboardData(text: token.uploadUrl));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Link copiado para a área de transferência!'),
          backgroundColor: AppColors.status.success,
        ),
      );
    }
  }

  Future<void> _sendWhatsApp(UploadToken token) async {
    try {
      // Buscar dados do cliente para pegar o telefone/WhatsApp
      final clientResponse = await _clientService.getClientById(token.clientId);
      
      String? phone;
      if (clientResponse.success && clientResponse.data != null) {
        phone = clientResponse.data!.whatsapp ?? clientResponse.data!.phone;
      }
      
      final message = 'Olá! Segue o link para envio de documentos:\n${token.uploadUrl}';
      final encodedMessage = Uri.encodeComponent(message);
      
      String whatsappUrl;
      if (phone != null && phone.isNotEmpty) {
        // Remove caracteres não numéricos do telefone
        final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
        whatsappUrl = 'https://wa.me/$cleanPhone?text=$encodedMessage';
      } else {
        // Se não tiver telefone, abre sem número específico
        whatsappUrl = 'https://wa.me/?text=$encodedMessage';
      }
      
      final uri = Uri.parse(whatsappUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Não foi possível abrir o WhatsApp'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir WhatsApp: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _openInBrowser(UploadToken token) async {
    try {
      final uri = Uri.parse(token.uploadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Não foi possível abrir o link'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir link: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _sendEmail(UploadToken token) async {
    try {
      // Buscar dados do cliente para pegar o email
      final clientResponse = await _clientService.getClientById(token.clientId);
      
      String? clientEmail;
      if (clientResponse.success && clientResponse.data != null) {
        clientEmail = clientResponse.data!.email;
      }
      
      if (clientEmail == null || clientEmail.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Cliente não possui email cadastrado'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
        return;
      }
      
      final subject = 'Link para envio de documentos';
      final body = 'Olá ${token.clientName}!\n\nSegue o link para envio de documentos:\n${token.uploadUrl}';
      
      final encodedSubject = Uri.encodeComponent(subject);
      final encodedBody = Uri.encodeComponent(body);
      final gmailUrl = 'https://mail.google.com/mail/?view=cm&to=$clientEmail&su=$encodedSubject&body=$encodedBody';
      
      final uri = Uri.parse(gmailUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Não foi possível abrir o Gmail'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao abrir Gmail: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  Future<void> _revokeToken(UploadToken token) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revogar Link'),
        content: Text(
          'Tem certeza que deseja revogar o link público para ${token.clientName}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.status.error,
            ),
            child: const Text('Revogar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await _documentService.revokeUploadToken(token.id);
      
      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Link revogado com sucesso!'),
              backgroundColor: AppColors.status.success,
            ),
          );
          // Remover token da lista local
          setState(() {
            _tokens.removeWhere((t) => t.id == token.id);
          });
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? 'Erro ao revogar link'),
              backgroundColor: AppColors.status.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao revogar link: ${e.toString()}'),
            backgroundColor: AppColors.status.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: ThemeHelpers.borderLightColor(context),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Links Públicos de Upload',
                        style: GoogleFonts.poppins(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Crie links para clientes enviarem documentos',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Conteúdo
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      debugPrint('🔗 [UPLOAD_TOKENS_MODAL] Renderizando conteúdo (não está carregando)');
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Formulário de criação - sempre mostrar
                            _buildCreateForm(context, theme, isDark),
                            
                            const SizedBox(height: 32),
                            
                            // Lista de tokens
                            Text(
                              'Links Criados',
                              style: GoogleFonts.poppins(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: ThemeHelpers.textColor(context),
                              ),
                            ),
                            const SizedBox(height: 16),
                            
                            if (_tokens.isEmpty)
                              _buildEmptyState(context, theme)
                            else
                              ..._tokens.map((token) => _buildTokenCard(
                                    context,
                                    theme,
                                    isDark,
                                    token,
                                  )),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateForm(
    BuildContext context,
    ThemeData theme,
    bool isDark,
  ) {
    debugPrint('🔗 [UPLOAD_TOKENS_MODAL] _buildCreateForm - Construindo formulário');
    debugPrint('   - _selectedClientId: $_selectedClientId');
    debugPrint('   - _selectedClientName: $_selectedClientName');
    
    return Card(
      elevation: 0,
      color: ThemeHelpers.cardBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Criar Novo Link',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 24),
              
              // Vínculo - Cliente (obrigatório para links públicos)
              Text(
                'Cliente *',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  debugPrint('🔗 [UPLOAD_TOKENS_MODAL] Construindo EntitySelector');
                  debugPrint('   - type: client');
                  debugPrint('   - selectedId: $_selectedClientId');
                  debugPrint('   - selectedName: $_selectedClientName');
                  
                  return EntitySelector(
                    type: 'client',
                    selectedId: _selectedClientId,
                    selectedName: _selectedClientName,
                    onSelected: (id, name) {
                      debugPrint('🔗 [UPLOAD_TOKENS_MODAL] ⭐ CALLBACK onSelected chamado!');
                      debugPrint('   - ID recebido: "$id"');
                      debugPrint('   - Name recebido: "$name"');
                      debugPrint('   - ID length: ${id.length}');
                      debugPrint('   - ID trim length: ${id.trim().length}');
                      
                      if (id.isEmpty || id.trim().isEmpty) {
                        debugPrint('❌ [UPLOAD_TOKENS_MODAL] ID do cliente está vazio!');
                      } else {
                        debugPrint('✅ [UPLOAD_TOKENS_MODAL] ID válido, atualizando estado');
                      }
                      
                      setState(() {
                        _selectedClientId = id.trim();
                        _selectedClientName = name;
                        debugPrint('✅ [UPLOAD_TOKENS_MODAL] Estado atualizado:');
                        debugPrint('   - _selectedClientId: $_selectedClientId');
                        debugPrint('   - _selectedClientName: $_selectedClientName');
                      });
                    },
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // Dias de expiração
              Text(
                'Dias de validade',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ThemeHelpers.textColor(context),
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _expirationDays.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '$_expirationDays dias',
                onChanged: (value) {
                  setState(() {
                    _expirationDays = value.toInt();
                  });
                },
              ),
              Text(
                'O link expirará em $_expirationDays dias',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Observações
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Observações (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
                maxLength: 500,
              ),
              
              const SizedBox(height: 16),
              
              // Botão criar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isCreating || _selectedClientId == null || _selectedClientId!.isEmpty)
                      ? null
                      : _createToken,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ).copyWith(
                    backgroundColor: (_selectedClientId == null || _selectedClientId!.isEmpty)
                        ? MaterialStateProperty.all(ThemeHelpers.borderLightColor(context))
                        : null,
                  ),
                  child: _isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          'Criar Link Público',
                          style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokenCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    UploadToken token,
  ) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final isExpired = token.isExpired || token.status != UploadTokenStatus.active;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: ThemeHelpers.cardBackgroundColor(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isExpired
              ? AppColors.status.error.withOpacity(0.3)
              : ThemeHelpers.borderLightColor(context),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        token.clientName,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: ThemeHelpers.textColor(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'CPF: ${token.clientCpfMasked}',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: ThemeHelpers.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? AppColors.status.error.withOpacity(0.1)
                        : AppColors.status.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    token.status.label,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isExpired
                          ? AppColors.status.error
                          : AppColors.status.success,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
            
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Expira em: ${dateFormat.format(token.expiresAt)}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: ThemeHelpers.textSecondaryColor(context),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.description,
                  size: 16,
                  color: ThemeHelpers.textSecondaryColor(context),
                ),
                const SizedBox(width: 8),
                Text(
                  '${token.documentsUploaded} doc(s)',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                ),
              ],
            ),
            
            if (token.notes != null && token.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Observações: ${token.notes}',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: ThemeHelpers.textSecondaryColor(context),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            
            const SizedBox(height: 12),
            
            // URL do link
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ThemeHelpers.borderLightColor(context).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: ThemeHelpers.borderLightColor(context),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 16,
                    color: ThemeHelpers.textSecondaryColor(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SelectableText(
                      token.uploadUrl,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: ThemeHelpers.textColor(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Botões de ação
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isExpired ? null : () => _copyLink(token),
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copiar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isExpired ? null : () => _openInBrowser(token),
                        icon: const Icon(Icons.open_in_browser, size: 18),
                        label: const Text('Abrir'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isExpired ? null : () => _sendWhatsApp(token),
                        icon: const Icon(Icons.chat, size: 18),
                        label: const Text('WhatsApp'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: isExpired ? null : () => _sendEmail(token),
                        icon: const Icon(Icons.email, size: 18),
                        label: const Text('Email'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: OutlinedButton(
                        onPressed: isExpired ? null : () => _revokeToken(token),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.status.error,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Icon(Icons.block, size: 20),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.link_off,
              size: 64,
              color: ThemeHelpers.textSecondaryColor(context),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhum link público criado',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: ThemeHelpers.textColor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Crie um link para permitir que clientes enviem documentos',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: ThemeHelpers.textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

