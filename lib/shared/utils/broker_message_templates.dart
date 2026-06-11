/// Templates de mensagem prontos para o corretor copiar/enviar.
class BrokerMessageTemplates {
  BrokerMessageTemplates._();

  static String leadFollowUp({
    required String leadName,
    String? propertyTitle,
  }) {
    final prop = propertyTitle?.trim();
    if (prop != null && prop.isNotEmpty) {
      return 'Olá $leadName! Vi seu interesse no imóvel $prop. '
          'Posso te passar mais detalhes ou agendar uma visita?';
    }
    return 'Olá $leadName! Vi seu interesse. '
        'Posso te ajudar a encontrar o imóvel ideal — quando podemos conversar?';
  }

  static String propertyShare({
    required String propertyTitle,
    String? address,
    String? code,
  }) {
    final parts = <String>[
      '🏠 *$propertyTitle*',
      if (code != null && code.trim().isNotEmpty) 'Código: ${code.trim()}',
      if (address != null && address.trim().isNotEmpty) address.trim(),
      '',
      'Ficou interessado(a)? Me chama que agendo uma visita!',
    ];
    return parts.join('\n');
  }

  static String matchesShare({
    required String clientName,
    required List<String> propertyLines,
  }) {
    final buf = StringBuffer('Olá $clientName! Separei imóveis para você:\n\n');
    for (var i = 0; i < propertyLines.length; i++) {
      buf.writeln('${i + 1}. ${propertyLines[i]}');
    }
    buf.write('\nQual te interessou mais?');
    return buf.toString();
  }
}
