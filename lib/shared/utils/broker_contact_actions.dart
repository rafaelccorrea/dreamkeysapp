import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ações de contato usadas pelo corretor (ligar, WhatsApp, maps).
class BrokerContactActions {
  BrokerContactActions._();

  static String digitsOnly(String? raw) =>
      (raw ?? '').replaceAll(RegExp(r'\D'), '');

  /// Formata um telefone brasileiro para exibição: `(11) 91234-5678`.
  /// Mantém o DDI quando presente e cai para o valor original se não
  /// reconhecer o formato (ex.: número internacional).
  static String formatBrazilPhone(String? raw) {
    var d = digitsOnly(raw);
    if (d.isEmpty) return raw?.trim() ?? '';
    var prefix = '';
    if (d.length > 11 && d.startsWith('55')) {
      prefix = '+55 ';
      d = d.substring(2);
    }
    if (d.length == 11) {
      return '$prefix(${d.substring(0, 2)}) ${d.substring(2, 7)}-${d.substring(7)}';
    }
    if (d.length == 10) {
      return '$prefix(${d.substring(0, 2)}) ${d.substring(2, 6)}-${d.substring(6)}';
    }
    return raw?.trim() ?? d;
  }

  static Future<bool> callPhone(BuildContext context, String? phone) async {
    final d = digitsOnly(phone);
    if (d.length < 10) {
      _snack(context, 'Telefone inválido ou não informado.');
      return false;
    }
    final uri = Uri.parse('tel:$d');
    if (!await launchUrl(uri)) {
      _snack(context, 'Não foi possível abrir o discador.');
      return false;
    }
    return true;
  }

  static Future<bool> openWhatsApp(
    BuildContext context,
    String? phone, {
    String? message,
  }) async {
    final d = digitsOnly(phone);
    if (d.length < 10) {
      _snack(context, 'WhatsApp indisponível — telefone não informado.');
      return false;
    }
    final text = message != null && message.trim().isNotEmpty
        ? '?text=${Uri.encodeComponent(message.trim())}'
        : '';
    final uri = Uri.parse('https://wa.me/$d$text');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack(context, 'Não foi possível abrir o WhatsApp.');
      return false;
    }
    return true;
  }

  static Future<bool> openMaps(BuildContext context, String address) async {
    final q = address.trim();
    if (q.isEmpty) {
      _snack(context, 'Endereço não informado.');
      return false;
    }
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _snack(context, 'Não foi possível abrir o mapa.');
      return false;
    }
    return true;
  }

  static Future<bool> shareText(BuildContext context, String text) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final uri = Uri.parse('mailto:?body=${Uri.encodeComponent(t)}');
    if (await launchUrl(uri)) return true;
    await Clipboard.setData(ClipboardData(text: t));
    _snack(context, 'Texto copiado — cole no WhatsApp ou e-mail.');
    return true;
  }

  static void _snack(BuildContext context, String msg) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}
