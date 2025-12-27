import 'package:flutter/material.dart';
import '../../../../shared/services/property_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_helpers.dart';

/// Widget para alternar publicação da propriedade no site
class PropertyPublicToggle extends StatefulWidget {
  final String propertyId;
  final bool initialValue;
  final PropertyStatus propertyStatus;
  final bool isActive;
  final int? imageCount;
  final VoidCallback? onSuccess;
  final Function(String)? onError;
  final String size; // 'small' | 'medium' | 'large'

  const PropertyPublicToggle({
    super.key,
    required this.propertyId,
    required this.initialValue,
    required this.propertyStatus,
    this.isActive = true,
    this.imageCount,
    this.onSuccess,
    this.onError,
    this.size = 'medium',
  });

  @override
  State<PropertyPublicToggle> createState() => _PropertyPublicToggleState();
}

class _PropertyPublicToggleState extends State<PropertyPublicToggle> {
  late bool _isPublic;
  bool _isLoading = false;
  final PropertyService _propertyService = PropertyService.instance;

  @override
  void initState() {
    super.initState();
    _isPublic = widget.initialValue;
  }

  bool get _canPublish {
    if (!widget.isActive) return false;
    if (widget.propertyStatus != PropertyStatus.available) return false;
    final validImages = widget.imageCount ?? 0;
    if (validImages < 5) return false;
    return true;
  }

  String? get _cannotPublishReason {
    if (!widget.isActive) {
      return 'Propriedade deve estar ativa';
    }
    if (widget.propertyStatus != PropertyStatus.available) {
      return 'Status deve ser "Disponível"';
    }
    final validImages = widget.imageCount ?? 0;
    if (validImages < 5) {
      return 'Necessário ter 5 imagens (atualmente: $validImages)';
    }
    return null;
  }

  Future<void> _togglePublic() async {
    if (!_canPublish && !_isPublic) {
      final reason = _cannotPublishReason;
      if (reason != null && widget.onError != null) {
        widget.onError!(reason);
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _propertyService.updateProperty(
        widget.propertyId,
        {'isAvailableForSite': !_isPublic},
      );

      if (mounted) {
        if (response.success) {
          setState(() {
            _isPublic = !_isPublic;
          });
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          }
        } else {
          if (widget.onError != null) {
            widget.onError!(response.message ?? 'Erro ao atualizar publicação');
          }
        }
      }
    } catch (e) {
      if (mounted && widget.onError != null) {
        widget.onError!('Erro de conexão');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = !_canPublish && !_isPublic;

    return Tooltip(
      message: isDisabled
          ? _cannotPublishReason ?? 'Não é possível publicar esta propriedade'
          : _isPublic
              ? 'Publicado no site Dream Keys'
              : 'Publicar no site Dream Keys',
      child: SwitchListTile(
        title: const Text('Disponível no Site Dream Keys'),
        subtitle: _isPublic
            ? const Text('Propriedade visível no site público')
            : Text(
                isDisabled
                    ? _cannotPublishReason ?? ''
                    : 'Propriedade não está no site público',
              ),
        value: _isPublic,
        onChanged: isDisabled && !_isPublic
            ? null
            : _isLoading
                ? null
                : (_) => _togglePublic(),
        secondary: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _isPublic ? Icons.public : Icons.public_off,
                color: _isPublic
                    ? AppColors.status.success
                    : ThemeHelpers.textSecondaryColor(context),
              ),
      ),
    );
  }
}

