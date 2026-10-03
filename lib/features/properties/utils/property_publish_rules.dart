import '../../../shared/services/property_service.dart';

/// Mínimo de fotos para publicar no site — regra do web (`canPublishProperty`
/// em `PropertiesPage.tsx`).
const int kMinPublishableSitePhotos = 5;

/// Fotos que contam para publicar: `publishableImageCount` da API (a
/// listagem recorta `images`); sem ele, conta as fotos válidas que vieram
/// (com URL, sem vídeo, sem foto oculta do site) — o mesmo fallback do web.
int publishableSitePhotoCount(Property property) {
  final fromApi = property.publishableImageCount;
  if (fromApi != null) return fromApi;
  final images = property.images ?? const <PropertyImage>[];
  return images
      .where((img) =>
          img.url.trim().isNotEmpty &&
          img.mediaType != 'video' &&
          img.showOnPublicSite != false)
      .length;
}

/// Motivo que impede PUBLICAR no site, ou `null` quando pode. Ocultar nunca
/// é bloqueado. Mesma ordem e textos do web.
String? sitePublishBlockReason(Property property) {
  if (!property.isActive) return 'Propriedade deve estar ativa';
  if (property.statusRaw != PropertyStatus.available.value) {
    return 'Status deve ser "Disponível"';
  }
  final count = publishableSitePhotoCount(property);
  if (count < kMinPublishableSitePhotos) {
    return 'Necessário ter $kMinPublishableSitePhotos imagens '
        '(atualmente: $count)';
  }
  return null;
}

/// Motivo que impede "Marcar como vendido/alugado" pelo atalho, ou `null`.
/// O web esconde o atalho enquanto há aprovação financeira pendente.
String? financialApprovalLockReason(Property property) {
  if (property.hasPendingFinancialApproval == true) {
    return 'Há uma aprovação financeira pendente para este imóvel. Aguarde a '
        'decisão do financeiro para marcar como vendido ou alugado.';
  }
  return null;
}
