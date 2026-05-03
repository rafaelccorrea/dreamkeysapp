import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../models/appointment_model.dart';

/// Helpers visuais e textuais de agendamentos — reutilizados pelo calendário,
/// criação, edição, detalhes e modal de convites para garantir um design coeso.
class AppointmentVisuals {
  AppointmentVisuals._();

  /// Paleta curada — combina com o sistema cromático do app e o tom de marca.
  /// Cada cor possui um rótulo humano para o seletor.
  static const List<AppointmentColorOption> palette = [
    AppointmentColorOption('#D32F2F', 'Vermelho marca'),
    AppointmentColorOption('#3B82F6', 'Azul'),
    AppointmentColorOption('#10B981', 'Verde'),
    AppointmentColorOption('#F59E0B', 'Âmbar'),
    AppointmentColorOption('#8B5CF6', 'Roxo'),
    AppointmentColorOption('#06B6D4', 'Ciano'),
    AppointmentColorOption('#84CC16', 'Lima'),
    AppointmentColorOption('#F97316', 'Laranja'),
    AppointmentColorOption('#EC4899', 'Rosa'),
    AppointmentColorOption('#6366F1', 'Índigo'),
  ];

  /// Converte hexadecimal `#RRGGBB` em [Color] (com fallback para o vermelho marca).
  static Color colorFromHex(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return const Color(0xFFD32F2F);
    }
  }

  /// Ícone associado ao tipo do agendamento — comunica intenção visualmente.
  static IconData iconFor(AppointmentType type) {
    switch (type) {
      case AppointmentType.visit:
        return Icons.home_work_rounded;
      case AppointmentType.meeting:
        return Icons.groups_rounded;
      case AppointmentType.inspection:
        return Icons.fact_check_rounded;
      case AppointmentType.documentation:
        return Icons.description_rounded;
      case AppointmentType.signature:
        return Icons.draw_rounded;
      case AppointmentType.maintenance:
        return Icons.build_rounded;
      case AppointmentType.marketing:
        return Icons.campaign_rounded;
      case AppointmentType.training:
        return Icons.school_rounded;
      case AppointmentType.other:
        return Icons.event_note_rounded;
    }
  }

  /// Ícone para o nível de visibilidade.
  static IconData iconForVisibility(AppointmentVisibility v) {
    switch (v) {
      case AppointmentVisibility.public:
        return Icons.public_rounded;
      case AppointmentVisibility.private:
        return Icons.lock_outline_rounded;
      case AppointmentVisibility.team:
        return Icons.people_alt_rounded;
    }
  }

  /// Descrição curta para a visibilidade, usada no seletor.
  static String visibilityDescription(AppointmentVisibility v) {
    switch (v) {
      case AppointmentVisibility.public:
        return 'Visível para toda a empresa';
      case AppointmentVisibility.private:
        return 'Apenas você visualiza';
      case AppointmentVisibility.team:
        return 'Compartilhado com participantes';
    }
  }

  /// Mapa de cores para cada status — espelha o usado nos cards de calendário.
  static Color colorForStatus(AppointmentStatus s) {
    switch (s) {
      case AppointmentStatus.scheduled:
        return AppColors.status.warning;
      case AppointmentStatus.confirmed:
        return AppColors.status.info;
      case AppointmentStatus.inProgress:
        return AppColors.primary.primary;
      case AppointmentStatus.completed:
        return AppColors.status.success;
      case AppointmentStatus.cancelled:
      case AppointmentStatus.noShow:
        return AppColors.status.error;
    }
  }

  /// Ícone inteligente por status.
  static IconData iconForStatus(AppointmentStatus s) {
    switch (s) {
      case AppointmentStatus.scheduled:
        return Icons.schedule_rounded;
      case AppointmentStatus.confirmed:
        return Icons.check_circle_outline_rounded;
      case AppointmentStatus.inProgress:
        return Icons.play_circle_outline_rounded;
      case AppointmentStatus.completed:
        return Icons.task_alt_rounded;
      case AppointmentStatus.cancelled:
        return Icons.cancel_outlined;
      case AppointmentStatus.noShow:
        return Icons.do_not_disturb_on_outlined;
    }
  }

  /// Calcula um rótulo humano para a distância até o início do agendamento.
  /// Ex.: "Em 2 dias", "Em 30 minutos", "Acontece agora", "Há 1 dia".
  static String relativeTimeLabel(DateTime start, DateTime end) {
    final now = DateTime.now();

    if (now.isAfter(start) && now.isBefore(end)) {
      return 'Acontece agora';
    }

    if (start.isAfter(now)) {
      final diff = start.difference(now);
      if (diff.inMinutes < 1) return 'Começa agora';
      if (diff.inMinutes < 60) {
        return 'Em ${diff.inMinutes} min';
      }
      if (diff.inHours < 24) {
        final h = diff.inHours;
        return 'Em $h ${h == 1 ? 'hora' : 'horas'}';
      }
      final d = diff.inDays;
      if (d == 1) return 'Amanhã';
      if (d < 7) return 'Em $d dias';
      if (d < 30) {
        final w = (d / 7).floor();
        return 'Em $w ${w == 1 ? 'semana' : 'semanas'}';
      }
      final m = (d / 30).floor();
      return 'Em $m ${m == 1 ? 'mês' : 'meses'}';
    }

    final diff = now.difference(end);
    if (diff.inMinutes < 60) return 'Há ${diff.inMinutes} min';
    if (diff.inHours < 24) {
      final h = diff.inHours;
      return 'Há $h ${h == 1 ? 'hora' : 'horas'}';
    }
    final d = diff.inDays;
    if (d == 1) return 'Ontem';
    if (d < 7) return 'Há $d dias';
    if (d < 30) {
      final w = (d / 7).floor();
      return 'Há $w ${w == 1 ? 'semana' : 'semanas'}';
    }
    final m = (d / 30).floor();
    return 'Há $m ${m == 1 ? 'mês' : 'meses'}';
  }

  /// Duração humana (ex.: "1h 30min", "45 min", "2 dias").
  static String durationLabel(DateTime start, DateTime end) {
    final d = end.difference(start);
    if (d.inMinutes <= 0) return 'Imediato';
    if (d.inDays >= 1) {
      final hours = d.inHours.remainder(24);
      if (hours == 0) return '${d.inDays} ${d.inDays == 1 ? 'dia' : 'dias'}';
      return '${d.inDays}d ${hours}h';
    }
    if (d.inHours >= 1) {
      final mins = d.inMinutes.remainder(60);
      if (mins == 0) return '${d.inHours}h';
      return '${d.inHours}h ${mins}min';
    }
    return '${d.inMinutes} min';
  }

  /// Normaliza data em chave 'YYYY-MM-DD' usada nos mapas locais.
  static String dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Saudação contextual baseada na hora local.
  static String greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Bom dia';
    if (h < 18) return 'Boa tarde';
    return 'Boa noite';
  }

  /// Capitaliza a primeira letra (datas em pt_BR vêm em minúscula).
  static String capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// Texto formatado e capitalizado: ex. "Quinta, 15 de maio".
  static String formattedFullDate(DateTime d) {
    final f = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
    return capitalize(f);
  }

  /// Texto curto formatado: ex. "Qua, 15 mai".
  static String formattedShortDate(DateTime d) {
    final f = DateFormat('EEE, d MMM', 'pt_BR').format(d);
    return capitalize(f);
  }

  /// Hora formatada (HH:mm).
  static String formattedTime(DateTime d) => DateFormat('HH:mm').format(d);
}

/// Opção de cor da paleta com nome humano.
class AppointmentColorOption {
  final String hex;
  final String name;
  const AppointmentColorOption(this.hex, this.name);

  Color get color => AppointmentVisuals.colorFromHex(hex);
}
