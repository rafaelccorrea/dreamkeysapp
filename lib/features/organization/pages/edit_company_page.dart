import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helpers.dart';
import '../../../shared/services/cep_service.dart';
import '../../../shared/widgets/app_error_state.dart';
import '../../../shared/widgets/app_scaffold.dart';
import '../../../shared/widgets/skeleton_box.dart';
import '../services/company_admin_service.dart';

/// Editar empresa — paridade com `EditCompanyPage.tsx` do imobx-front.
///
/// Mesmos campos e obrigatoriedades do schema yup do web: nome, CNPJ
/// (validado, aceita o alfanumérico de 2026), razão social, endereço,
/// cidade, UF e CEP obrigatórios; e-mail, telefone e descrição opcionais.
/// Busca de CEP (ViaCEP), coordenadas pelo endereço (GET /companies/geocode)
/// ou pela localização do aparelho, logo (enviada ao salvar, como no web) e
/// marca d'água PNG (enviada na hora, como o `WatermarkUpload` do web).
/// Grava com PUT /companies/:id. Só admin/master chegam aqui (o back
/// também exige `@Roles(MASTER, ADMIN)`).
///
/// Devolve `true` no `pop` quando salvou, para quem abriu recarregar.
class EditCompanyPage extends StatefulWidget {
  const EditCompanyPage({super.key, required this.companyId});

  final String companyId;

  @override
  State<EditCompanyPage> createState() => _EditCompanyPageState();
}

class _EditCompanyPageState extends State<EditCompanyPage> {
  static const double _padH = 16;

  /// Em tela larga a coluna do formulário para aqui e centraliza.
  static const double _maxContentWidth = 720;
  static const int _logoMaxBytes = 5 * 1024 * 1024;
  static const int _watermarkMaxBytes = 2 * 1024 * 1024;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _cnpj = TextEditingController();
  final _corporateName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _description = TextEditingController();
  final _zipCode = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();

  bool _loading = true;
  String? _error;
  // Guardado junto da mensagem: sem o código HTTP não dá para distinguir
  // "sem permissão" de "servidor fora do ar".
  int _errorStatus = 0;
  bool _saving = false;
  bool _searchingCep = false;
  bool _geocoding = false;
  bool _locating = false;
  bool _watermarkBusy = false;
  bool _dirty = false;
  bool _autoValidate = false;

  String? _logoRaw;
  String? _logoUrl;
  File? _logoFile;
  String? _watermarkUrl;
  String _lastAutoCep = '';

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _brand =>
      _isDark ? AppColors.primary.primaryDarkMode : AppColors.primary.primary;

  Color get _confirm =>
      _isDark ? AppColors.status.successDarkMode : AppColors.status.success;

  Color get _danger =>
      _isDark ? AppColors.status.errorDarkMode : AppColors.status.error;

  Color get _fieldFill => _isDark
      ? AppColors.background.backgroundTertiaryDarkMode
      : AppColors.background.backgroundTertiary;

  List<TextEditingController> get _allControllers => [
        _name,
        _cnpj,
        _corporateName,
        _email,
        _phone,
        _description,
        _zipCode,
        _address,
        _city,
        _state,
        _latitude,
        _longitude,
      ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _allControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty && !_loading) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _errorStatus = 0;
    });
    final res = await CompanyAdminService.instance.getCompany(widget.companyId);
    if (!mounted) return;
    if (!res.success || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.message ?? 'Erro ao carregar empresa';
        _errorStatus = res.statusCode;
      });
      return;
    }
    final c = res.data!;
    for (final ctrl in _allControllers) {
      ctrl.removeListener(_markDirty);
    }
    _name.text = c.name;
    _cnpj.text = _maskCnpj(c.cnpj);
    _corporateName.text = c.corporateName;
    _email.text = c.email;
    _phone.text = c.phone.isEmpty ? '' : _maskPhoneAuto(c.phone);
    _description.text = c.description;
    _zipCode.text = _maskCep(c.zipCode);
    _address.text = c.address;
    _city.text = c.city;
    _state.text = c.state.toUpperCase();
    _latitude.text = c.latitude?.toString() ?? '';
    _longitude.text = c.longitude?.toString() ?? '';
    _lastAutoCep = c.zipCode.replaceAll(RegExp(r'\D'), '');
    for (final ctrl in _allControllers) {
      ctrl.addListener(_markDirty);
    }
    setState(() {
      _logoRaw = c.logoRaw;
      _logoUrl = c.logoUrl;
      _watermarkUrl = c.watermarkUrl;
      _loading = false;
      _dirty = false;
    });
  }

  // ─── Máscaras / validação (espelho de utils/masks.ts do web) ─────────────

  /// CNPJ alfanumérico (SERPRO 2026): XX.XXX.XXX/XXXX-XX com letras e
  /// números — igual ao `maskCNPJ` do web.
  static String _maskCnpj(String value) {
    final clean = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final s = clean.length > 14 ? clean.substring(0, 14) : clean;
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i == 2 || i == 5) b.write('.');
      if (i == 8) b.write('/');
      if (i == 12) b.write('-');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// `validateCNPJ` do web: 14 caracteres, letras valem ASCII - 48.
  static bool _validCnpj(String cnpj) {
    final clean = cnpj.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (clean.length != 14) return false;
    int dv(String base) {
      const weights = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
      final start = 13 - base.length;
      var sum = 0;
      for (var i = 0; i < base.length; i++) {
        sum += (base.codeUnitAt(i) - 48) * weights[start + i];
      }
      final r = sum % 11;
      return (r == 0 || r == 1) ? 0 : 11 - r;
    }

    final d1 = int.tryParse(clean[12]);
    if (d1 == null || dv(clean.substring(0, 12)) != d1) return false;
    final d2 = int.tryParse(clean[13]);
    if (d2 == null || dv(clean.substring(0, 13)) != d2) return false;
    return true;
  }

  static String _maskCep(String value) {
    final d = value.replaceAll(RegExp(r'\D'), '');
    final s = d.length > 8 ? d.substring(0, 8) : d;
    if (s.length <= 5) return s;
    return '${s.substring(0, 5)}-${s.substring(5)}';
  }

  /// `maskPhoneAuto` do web: 12-13 dígitos com 55 → últimos 11; 11 →
  /// celular; senão fixo (10).
  static String _maskPhoneAuto(String value) {
    var d = value.replaceAll(RegExp(r'\D'), '');
    if (d.length >= 12 && d.startsWith('55')) {
      d = d.substring(d.length - 11);
    }
    if (d.length > 11) d = d.substring(0, 11);
    if (d.isEmpty) return '';
    if (d.length <= 2) return '($d';
    final ddd = d.substring(0, 2);
    final rest = d.substring(2);
    if (d.length == 11) {
      return '($ddd) ${rest.substring(0, 5)}-${rest.substring(5)}';
    }
    if (rest.length <= 4) return '($ddd) $rest';
    return '($ddd) ${rest.substring(0, 4)}-${rest.substring(4)}';
  }

  static final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  String? _required(String? v, String message) =>
      (v ?? '').trim().isEmpty ? message : null;

  // ─── Ações ───────────────────────────────────────────────────────────────

  void _toast(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            success ? AppColors.status.success : AppColors.status.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _onCepChanged(String raw) {
    final clean = raw.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 8) {
      if (clean.length < 8) _lastAutoCep = '';
      return;
    }
    if (_lastAutoCep == clean) return;
    _lastAutoCep = clean;
    _searchCep(clean);
  }

  Future<void> _searchCep([String? cepArg]) async {
    final cep = (cepArg ?? _zipCode.text).replaceAll(RegExp(r'\D'), '');
    if (cep.length != 8) {
      _toast('CEP inválido. Digite os 8 dígitos.');
      return;
    }
    setState(() => _searchingCep = true);
    final result = await CepService.instance.searchCep(cep);
    if (!mounted) return;
    setState(() => _searchingCep = false);
    if (result == null) {
      _toast('CEP não encontrado');
      return;
    }
    _address.text = result.street ?? '';
    _city.text = result.city ?? '';
    _state.text = (result.state ?? '').toUpperCase();
    _toast('Endereço encontrado!', success: true);
  }

  Future<void> _fetchCoordinates() async {
    final address = _address.text.trim();
    final city = _city.text.trim();
    final state = _state.text.trim();
    final zip = _zipCode.text.replaceAll(RegExp(r'\D'), '');
    if (address.isEmpty && city.isEmpty && zip.isEmpty) {
      _toast('Preencha o endereço, cidade ou CEP antes de buscar.');
      return;
    }
    setState(() => _geocoding = true);
    final res = await CompanyAdminService.instance.geocode(
      address: address,
      city: city,
      state: state,
      zipCode: zip,
    );
    if (!mounted) return;
    setState(() => _geocoding = false);
    if (!res.success) {
      _toast('Erro ao buscar coordenadas. Tente novamente.');
      return;
    }
    final coords = res.data;
    if (coords == null) {
      _toast('Endereço não encontrado. Tente ajustar ou informar manualmente.');
      return;
    }
    _latitude.text = coords.latitude.toString();
    _longitude.text = coords.longitude.toString();
    _toast('Coordenadas obtidas com sucesso!', success: true);
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _toast('Ative a localização do dispositivo.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _toast('Permissão de localização negada. Habilite nas configurações.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      _latitude.text = pos.latitude.toString();
      _longitude.text = pos.longitude.toString();
      _toast(
        'Localização obtida! (precisão: ${pos.accuracy.round()}m)',
        success: true,
      );
    } catch (_) {
      _toast('Não foi possível obter sua localização.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickLogo() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final file = File(path);
      if (await file.length() > _logoMaxBytes) {
        _toast('A imagem deve ter no máximo 5MB');
        return;
      }
      if (!mounted) return;
      setState(() {
        _logoFile = file;
        _dirty = true;
      });
    } catch (_) {
      _toast('Erro ao processar imagem. Tente novamente.');
    }
  }

  Future<void> _pickWatermark() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png'],
        allowMultiple: false,
      );
      final path = result?.files.single.path;
      if (path == null) return;
      if (!path.toLowerCase().endsWith('.png')) {
        _toast('Apenas arquivos PNG são permitidos para marca d\'água');
        return;
      }
      final file = File(path);
      if (await file.length() > _watermarkMaxBytes) {
        _toast('Arquivo muito grande. Tamanho máximo: 2MB');
        return;
      }
      if (!mounted) return;
      setState(() => _watermarkBusy = true);
      final res = await CompanyAdminService.instance.uploadWatermark(
        widget.companyId,
        file,
      );
      if (!mounted) return;
      setState(() => _watermarkBusy = false);
      if (res.success) {
        setState(() => _watermarkUrl = res.data);
        _toast('Marca d\'água atualizada com sucesso!', success: true);
      } else {
        _toast(res.message ?? 'Erro ao fazer upload da marca d\'água');
      }
    } catch (_) {
      if (mounted) setState(() => _watermarkBusy = false);
      _toast('Erro ao fazer upload da marca d\'água');
    }
  }

  Future<void> _removeWatermark() async {
    final ok = await _confirmSheet(
      title: 'Remover marca d\'água?',
      message: 'As novas fotos de imóveis deixam de receber a marca.',
      confirmLabel: 'Remover',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    setState(() => _watermarkBusy = true);
    final res =
        await CompanyAdminService.instance.removeWatermark(widget.companyId);
    if (!mounted) return;
    setState(() => _watermarkBusy = false);
    if (res.success) {
      setState(() => _watermarkUrl = null);
      _toast('Marca d\'água removida com sucesso!', success: true);
    } else {
      _toast(res.message ?? 'Erro ao remover marca d\'água');
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) {
      setState(() => _autoValidate = true);
      _toast('Revise os campos destacados.');
      return;
    }
    setState(() => _saving = true);

    var logo = _logoRaw;
    if (_logoFile != null) {
      final up = await CompanyAdminService.instance.uploadLogo(
        widget.companyId,
        _logoFile!,
      );
      if (!mounted) return;
      if (!up.success) {
        setState(() => _saving = false);
        _toast(up.message ?? 'Erro ao atualizar empresa');
        return;
      }
      logo = up.data ?? logo;
    }

    final lat = double.tryParse(_latitude.text.trim().replaceAll(',', '.'));
    final lng = double.tryParse(_longitude.text.trim().replaceAll(',', '.'));
    final phone = _phone.text.trim();
    final email = _email.text.trim();

    // Mesmos nomes do payload do web (CreateCompanyDto). E-mail e telefone
    // vazios não vão: o DTO valida o formato de qualquer string enviada.
    final payload = <String, dynamic>{
      'name': _name.text.trim(),
      'cnpj': _maskCnpj(_cnpj.text),
      'corporateName': _corporateName.text.trim(),
      'address': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim().toUpperCase(),
      'zipCode': _maskCep(_zipCode.text),
      'description': _description.text.trim(),
      if (phone.isNotEmpty) 'phone': _maskPhoneAuto(phone),
      if (email.isNotEmpty) 'email': email,
      if (logo != null && logo.isNotEmpty) 'logo': logo,
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
    };

    final res = await CompanyAdminService.instance.updateCompany(
      widget.companyId,
      payload,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      _toast('Empresa atualizada com sucesso!', success: true);
      _dirty = false;
      Navigator.of(context).pop(true);
    } else {
      _toast(res.message ?? 'Erro ao atualizar empresa');
    }
  }

  Future<bool?> _confirmSheet({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ThemeHelpers.cardBackgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final tone = destructive ? _danger : _confirm;
        final mq = MediaQuery.of(ctx);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            // Teto: em landscape/tela baixa o texto rola e os botões ficam.
            constraints: BoxConstraints(maxHeight: mq.size.height * 0.88),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(_padH, 20, _padH, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: ThemeHelpers.textColor(ctx),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            message,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ThemeHelpers.textSecondaryColor(ctx),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            foregroundColor:
                                ThemeHelpers.textSecondaryColor(ctx),
                            side: BorderSide(
                              color: ThemeHelpers.borderColor(ctx),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'Cancelar',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: tone,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(13),
                            ),
                          ),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              confirmLabel,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await _confirmSheet(
      title: 'Descartar alterações?',
      message: 'As mudanças feitas nesta empresa ainda não foram salvas.',
      confirmLabel: 'Descartar',
      destructive: true,
    );
    if (discard == true && mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Teclado aberto em tela baixa (landscape): a barra sai para o campo em
    // foco caber; volta sozinha quando o teclado fecha.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final hideBar = keyboardOpen && MediaQuery.sizeOf(context).height < 520;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: AppScaffold(
        title: 'Editar empresa',
        showBottomNavigation: false,
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: _loading
              ? KeyedSubtree(
                  key: const ValueKey('loading'),
                  child: _buildSkeleton(),
                )
              : _error != null
                  ? KeyedSubtree(
                      key: const ValueKey('error'),
                      child: _buildError(),
                    )
                  : Column(
                      key: const ValueKey('form'),
                      children: [
                        Expanded(child: _buildForm()),
                        if (!hideBar) _buildSaveBar(),
                      ],
                    ),
        ),
      ),
    );
  }

  /// Tablet/landscape largo: a coluna para em [_maxContentWidth] e
  /// centraliza — campo de 1000dp não é formulário.
  EdgeInsets _pagePadding({double top = 0, double bottom = 0}) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w > _maxContentWidth ? (w - _maxContentWidth) / 2 : 0.0;
    return EdgeInsets.fromLTRB(side, top, side, bottom);
  }

  /// Espelha o formulário real: ficha da empresa no topo, capítulo 01 com a
  /// caixa da logo e os campos, capítulo 02 com endereço. Tudo numa coluna
  /// alinhada à esquerda (filho direto de ListView esticaria cada linha).
  Widget _buildSkeleton() => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: _pagePadding(top: 18, bottom: 16) +
            const EdgeInsets.symmetric(horizontal: _padH),
        children: const [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonText(width: 140, height: 10),
                  Spacer(),
                  SkeletonBox(width: 84, height: 22, borderRadius: 999),
                ],
              ),
              SizedBox(height: 12),
              SkeletonText(width: 200, height: 24),
              SizedBox(height: 8),
              SkeletonText(width: 230, height: 12),
              SizedBox(height: 8),
              SkeletonText(width: 260, height: 11),
              SizedBox(height: 30),
              Row(
                children: [
                  SkeletonText(width: 24, height: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 100, height: 10),
                        SizedBox(height: 6),
                        SkeletonText(width: 150, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  SkeletonBox(width: 72, height: 72, borderRadius: 16),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 170, height: 11),
                        SizedBox(height: 10),
                        SkeletonBox(width: 130, height: 40, borderRadius: 12),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              SkeletonBox(height: 56, borderRadius: 12),
              SizedBox(height: 12),
              SkeletonBox(height: 56, borderRadius: 12),
              SizedBox(height: 12),
              SkeletonBox(height: 56, borderRadius: 12),
              SizedBox(height: 30),
              Row(
                children: [
                  SkeletonText(width: 24, height: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonText(width: 100, height: 10),
                        SizedBox(height: 6),
                        SkeletonText(width: 170, height: 16),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),
              SkeletonBox(height: 56, borderRadius: 12),
              SizedBox(height: 12),
              SkeletonBox(height: 56, borderRadius: 12),
            ],
          ),
        ],
      );

  /// Erro com a causa real (permissão ≠ servidor fora ≠ sem internet) e
  /// "Tentar de novo" só quando repetir pode dar certo.
  Widget _buildError() {
    return AppErrorState.fromApi(
      message: _error,
      statusCode: _errorStatus,
      onRetry: _load,
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      autovalidateMode: _autoValidate
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      // Coluna inteira construída (não ListView preguiçoso): campo fora
      // da tela continua registrado no Form e entra na validação do
      // Salvar — antes, obrigatório rolado para longe passava em branco.
      child: SingleChildScrollView(
        padding: _pagePadding(top: 16, bottom: 28),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMasthead(),
            const SizedBox(height: 22),
            _separator(),
            const SizedBox(height: 20),
            _sectionHeader(
              index: '01',
              eyebrow: 'IDENTIFICAÇÃO',
              title: 'Dados da empresa',
              caption:
                  'Dados cadastrais, logo e contato exibidos no CRM e no site público.',
            ),
            const SizedBox(height: 16),
            _padded(_buildLogoRow()),
            const SizedBox(height: 16),
            _padded(
              _pair(
                _field(
                  controller: _name,
                  label: 'Nome da empresa *',
                  hint: 'Ex: Intellisys Filial São Paulo',
                  icon: LucideIcons.building2,
                  validator: (v) =>
                      _required(v, 'Nome da empresa é obrigatório'),
                ),
                _field(
                  controller: _cnpj,
                  label: 'CNPJ *',
                  hint: '00.000.000/0000-00',
                  icon: LucideIcons.idCard,
                  inputFormatters: [_CnpjFormatter()],
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return 'CNPJ é obrigatório';
                    if (!_validCnpj(v!)) return 'CNPJ inválido';
                    return null;
                  },
                ),
                minWidth: 460.0,
                aFlex: 5,
                bFlex: 4,
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              _field(
                controller: _corporateName,
                label: 'Razão social *',
                hint: 'Ex: Intellisys Imóveis Ltda',
                icon: LucideIcons.fileText,
                validator: (v) => _required(v, 'Razão social é obrigatória'),
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              _pair(
                _field(
                  controller: _email,
                  label: 'E-mail',
                  hint: 'contato@empresa.com.br',
                  icon: LucideIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return null;
                    return _emailRe.hasMatch(s) ? null : 'E-mail inválido';
                  },
                ),
                _field(
                  controller: _phone,
                  label: 'Telefone',
                  hint: '(00) 00000-0000',
                  icon: LucideIcons.phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [_PhoneFormatter()],
                  validator: (v) {
                    final d = (v ?? '').replaceAll(RegExp(r'\D'), '');
                    if (d.isEmpty) return null;
                    return (d.length == 10 || d.length == 11)
                        ? null
                        : 'Telefone deve estar no formato (XX) XXXXX-XXXX';
                  },
                ),
                minWidth: 460.0,
                aFlex: 5,
                bFlex: 4,
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              _field(
                controller: _description,
                label: 'Descrição',
                hint: 'Breve apresentação exibida no site público',
                icon: LucideIcons.alignLeft,
                maxLines: 3,
              ),
            ),
            const SizedBox(height: 26),
            _separator(),
            const SizedBox(height: 20),
            _sectionHeader(
              index: '02',
              eyebrow: 'LOCALIZAÇÃO',
              title: 'Endereço e coordenadas',
              caption:
                  'As coordenadas definem onde o check-in por localização é permitido.',
            ),
            const SizedBox(height: 16),
            _padded(
              _pair(
                _field(
                  controller: _zipCode,
                  label: 'CEP *',
                  hint: '00000-000',
                  icon: LucideIcons.mapPin,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_CepFormatter()],
                  onChanged: _onCepChanged,
                  suffix: _searchingCep
                      ? Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _brand,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Buscar CEP',
                          onPressed: () => _searchCep(),
                          icon: Icon(
                            LucideIcons.search,
                            size: 18,
                            color: _brand,
                          ),
                        ),
                  validator: (v) => _required(v, 'CEP é obrigatório'),
                ),
                _field(
                  controller: _state,
                  label: 'Estado (UF) *',
                  hint: 'SP',
                  icon: LucideIcons.map,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z]')),
                    LengthLimitingTextInputFormatter(2),
                    _UpperCaseFormatter(),
                  ],
                  validator: (v) {
                    final s = (v ?? '').trim();
                    if (s.isEmpty) return 'Estado é obrigatório';
                    if (s.length != 2) return 'Use a sigla do estado (ex: SP)';
                    return null;
                  },
                ),
                aFlex: 3,
                bFlex: 2,
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              _field(
                controller: _address,
                label: 'Endereço *',
                hint: 'Rua, número e complemento',
                icon: LucideIcons.house,
                validator: (v) => _required(v, 'Endereço é obrigatório'),
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              _field(
                controller: _city,
                label: 'Cidade *',
                hint: 'Ex: São Paulo',
                icon: LucideIcons.building,
                validator: (v) => _required(v, 'Cidade é obrigatória'),
              ),
            ),
            const SizedBox(height: 18),
            _padded(_subLabel('Coordenadas (check-in)')),
            const SizedBox(height: 10),
            _padded(
              _pair(
                _field(
                  controller: _latitude,
                  label: 'Latitude',
                  hint: '-23.5505',
                  icon: LucideIcons.locateFixed,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: _coordValidator,
                ),
                _field(
                  controller: _longitude,
                  label: 'Longitude',
                  hint: '-46.6333',
                  icon: LucideIcons.compass,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  validator: _coordValidator,
                ),
                forceRow: true,
              ),
            ),
            const SizedBox(height: 12),
            _padded(
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _inlineAction(
                    icon: LucideIcons.mapPinned,
                    label: 'Buscar pelo endereço',
                    busy: _geocoding,
                    onTap: _fetchCoordinates,
                  ),
                  _inlineAction(
                    icon: LucideIcons.locate,
                    label: 'Usar minha localização',
                    busy: _locating,
                    onTap: _fetchCurrentLocation,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            _separator(),
            const SizedBox(height: 20),
            _sectionHeader(
              index: '03',
              eyebrow: 'MARCA D\'ÁGUA',
              title: 'Marca d\'água',
              caption:
                  'Imagem aplicada automaticamente nas fotos dos imóveis. PNG de até 2MB.',
            ),
            const SizedBox(height: 16),
            _padded(_buildWatermarkRow()),
          ],
        ),
      ),
    );
  }

  String? _coordValidator(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return null;
    return double.tryParse(s.replaceAll(',', '.')) == null
        ? 'Número inválido'
        : null;
  }

  Widget _padded(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: _padH),
        child: child,
      );

  Widget _separator() => Container(
        height: 1,
        margin: const EdgeInsets.symmetric(horizontal: _padH),
        color: ThemeHelpers.borderColor(context).withValues(alpha: 0.35),
      );

  /// Duas colunas quando cabe (largura e escala de fonte); senão empilha.
  /// [minWidth] é a largura da linha a partir da qual os dois campos cabem
  /// sem cortar o conteúdo (CNPJ e e-mail pedem mais que CEP | UF).
  Widget _pair(
    Widget a,
    Widget b, {
    bool forceRow = false,
    double? minWidth,
    int aFlex = 1,
    int bFlex = 1,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return LayoutBuilder(
      builder: (context, box) {
        final threshold = minWidth ?? (forceRow ? 260.0 : 340.0);
        final twoCols = scale <= 1.3 && box.maxWidth >= threshold;
        if (!twoCols) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [a, const SizedBox(height: 12), b],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: aFlex, child: a),
            const SizedBox(width: 12),
            Expanded(flex: bFlex, child: b),
          ],
        );
      },
    );
  }

  /// Ficha viva da empresa: o título É o nome digitado, com CNPJ e
  /// cidade/UF logo abaixo, e um selo dizendo se há alteração sem salvar.
  Widget _buildMasthead() {
    final theme = Theme.of(context);
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return _padded(
      ListenableBuilder(
        listenable: Listenable.merge([_name, _cnpj, _city, _state]),
        builder: (context, _) {
          final name = _name.text.trim();
          final cnpj = _cnpj.text.trim();
          final place = [
            _city.text.trim(),
            _state.text.trim().toUpperCase(),
          ].where((s) => s.isNotEmpty).join('/');
          final meta = [
            if (cnpj.isNotEmpty) 'CNPJ $cnpj',
            if (place.isNotEmpty) place,
          ].join('  ·  ');
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.building2, size: 13, color: _brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'FICHA DA EMPRESA',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: _brand,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.8,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _SaveStateChip(dirty: _dirty),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                name.isEmpty ? 'Empresa sem nome' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.6,
                  height: 1.08,
                  color: name.isEmpty
                      ? secondary
                      : ThemeHelpers.textColor(context),
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textColor(context),
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                'Dados, logo e endereço aparecem no CRM, nos documentos e no '
                'site público. As coordenadas definem onde o check-in por '
                'localização vale.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondary,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionHeader({
    required String index,
    required String eyebrow,
    required String title,
    required String caption,
  }) {
    final theme = Theme.of(context);
    return _padded(
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            index,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
              color: _brand.withValues(alpha: 0.85),
              letterSpacing: -0.5,
              height: 1.0,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: _brand,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                    color: ThemeHelpers.textColor(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  caption,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: ThemeHelpers.textSecondaryColor(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: ThemeHelpers.textSecondaryColor(context),
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
            fontSize: 10.5,
          ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization textCapitalization = TextCapitalization.none,
    ValueChanged<String>? onChanged,
    Widget? suffix,
    int maxLines = 1,
  }) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    final radius = BorderRadius.circular(12);
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
      inputFormatters: inputFormatters,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      minLines: maxLines > 1 ? maxLines : 1,
      maxLines: maxLines,
      enabled: !_saving,
      style: TextStyle(
        color: ThemeHelpers.textColor(context),
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        alignLabelWithHint: maxLines > 1,
        labelStyle: TextStyle(
          color: secondary,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        hintStyle: TextStyle(
          color: secondary.withValues(alpha: 0.7),
          fontWeight: FontWeight.w500,
          fontSize: 13.5,
        ),
        errorMaxLines: 2,
        prefixIcon: maxLines > 1
            ? Padding(
                padding: const EdgeInsets.only(bottom: 44),
                child: Icon(icon, size: 17, color: secondary),
              )
            : Icon(icon, size: 17, color: secondary),
        suffixIcon: suffix,
        filled: true,
        fillColor: _fieldFill,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: _brand, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: _danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: _danger, width: 1.4),
        ),
      ),
    );
  }

  /// Ação de apoio (buscar, localizar, trocar imagem): contorno NEUTRO com o
  /// ícone na cor da marca — não compete com o Salvar verde nem se confunde
  /// com o "Remover" vermelho ao lado.
  Widget _inlineAction({
    required IconData icon,
    required String label,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final enabled = !(busy || _saving);
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: ThemeHelpers.textColor(context),
        minimumSize: const Size(0, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        side: BorderSide(color: ThemeHelpers.borderColor(context)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: _brand),
            )
          else
            Icon(icon, size: 16, color: enabled ? _brand : null),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePlate({
    required Widget child,
    double size = 72,
  }) {
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _fieldFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: ThemeHelpers.borderColor(context).withValues(alpha: 0.5),
        ),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  Widget _placeholder(IconData icon, String label) {
    final secondary = ThemeHelpers.textSecondaryColor(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: secondary),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildLogoRow() {
    final theme = Theme.of(context);
    Widget preview;
    if (_logoFile != null) {
      preview = Image.file(_logoFile!, fit: BoxFit.contain);
    } else if ((_logoUrl ?? '').isNotEmpty) {
      preview = Image.network(
        _logoUrl!,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => _placeholder(LucideIcons.image, 'Logo'),
      );
    } else {
      preview = _placeholder(LucideIcons.image, 'Logo');
    }
    final hasLogo = _logoFile != null || (_logoUrl ?? '').isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _imagePlate(child: preview),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PNG ou JPG de até 5MB. Aparece no CRM, nos documentos e no '
                'site público.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              _inlineAction(
                icon: LucideIcons.imagePlus,
                label: hasLogo ? 'Alterar logo' : 'Adicionar logo',
                busy: false,
                onTap: _pickLogo,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWatermarkRow() {
    final theme = Theme.of(context);
    final has = (_watermarkUrl ?? '').isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _imagePlate(
          child: _watermarkBusy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _brand,
                  ),
                )
              : has
                  ? Image.network(
                      _watermarkUrl!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          _placeholder(LucideIcons.droplet, 'PNG'),
                    )
                  : _placeholder(LucideIcons.droplet, 'PNG'),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                has
                    ? 'Marca d\'água ativa. Enviar outra substitui a atual.'
                    : 'Nenhuma marca d\'água cadastrada.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ThemeHelpers.textSecondaryColor(context),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _inlineAction(
                    icon: LucideIcons.upload,
                    label: has ? 'Trocar' : 'Enviar PNG',
                    busy: _watermarkBusy,
                    onTap: _pickWatermark,
                  ),
                  if (has)
                    OutlinedButton(
                      onPressed: (_watermarkBusy || _saving)
                          ? null
                          : _removeWatermark,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _danger,
                        minimumSize: const Size(0, 42),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        side: BorderSide(
                          color: _danger.withValues(alpha: 0.45),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.trash2, size: 16),
                          SizedBox(width: 8),
                          Text(
                            'Remover',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSaveBar() {
    // Texto sobre o verde de confirmação: branco no claro, grafite no escuro
    // (o verde do tema escuro é claro demais para letra branca).
    final onConfirm = ThemeHelpers.onPrimaryColor(context);
    // Com teclado aberto a barra encolhe um degrau: sobra mais formulário.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final height = keyboardOpen ? 46.0 : 52.0;
    final vPad = keyboardOpen ? 8.0 : 10.0;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        vPad,
        16,
        vPad + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: ThemeHelpers.cardBackgroundColor(context),
        border: Border(
          top: BorderSide(color: ThemeHelpers.borderColor(context)),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxContentWidth),
          child: Row(
            children: [
              OutlinedButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).maybePop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, height),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  foregroundColor: ThemeHelpers.textSecondaryColor(context),
                  side: BorderSide(color: ThemeHelpers.borderColor(context)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancelar',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: _confirm,
                    foregroundColor: onConfirm,
                    disabledBackgroundColor: _confirm.withValues(alpha: 0.55),
                    disabledForegroundColor: onConfirm,
                    minimumSize: Size(0, height),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: onConfirm,
                          ),
                        )
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.check, size: 17),
                              SizedBox(width: 8),
                              Text(
                                'Salvar alterações',
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
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
}

/// Selo do estado da edição no topo da ficha: "Não salvo" em âmbar quando
/// há alteração pendente; "Tudo salvo" neutro quando está como veio.
class _SaveStateChip extends StatelessWidget {
  const _SaveStateChip({required this.dirty});

  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = dirty
        ? (isDark
            ? AppColors.message.warningTextDarkMode
            : AppColors.message.warningText)
        : ThemeHelpers.textSecondaryColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: dirty ? color.withValues(alpha: 0.12) : Colors.transparent,
        border: Border.all(color: color.withValues(alpha: dirty ? 0.45 : 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            dirty ? LucideIcons.pencilLine : LucideIcons.check,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            dirty ? 'Não salvo' : 'Tudo salvo',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Formatadores ────────────────────────────────────────────────────────────

class _CnpjFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _EditCompanyPageState._maskCnpj(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _EditCompanyPageState._maskCep(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _PhoneFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _EditCompanyPageState._maskPhoneAuto(newValue.text);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
