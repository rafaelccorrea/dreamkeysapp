import 'package:flutter/material.dart';

/// Catálogo FIXO de tags do compromisso — precisa bater com
/// `imobx/src/appointments/appointment-tags.ts` (e `appointmentTags.ts` do
/// front). Valor fora da lista volta **400** do backend.
class AppointmentTag {
  final String value;
  final String label;

  /// Tom semântico (paridade com AppointmentDetailsPageStyles do web):
  /// drone/photo/video/tour_360 → info; keys/signage → warning;
  /// client_transport/owner_present → success; resto → slate.
  final Color tone;

  const AppointmentTag({
    required this.value,
    required this.label,
    required this.tone,
  });
}

const Color _info = Color(0xFF0EA5E9);
const Color _warning = Color(0xFFF59E0B);
const Color _success = Color(0xFF10B981);
const Color _slate = Color(0xFF64748B);

const List<AppointmentTag> kAppointmentTags = [
  AppointmentTag(value: 'drone', label: 'Drone', tone: _info),
  AppointmentTag(value: 'photo', label: 'Fotografia', tone: _info),
  AppointmentTag(value: 'video', label: 'Filmagem', tone: _info),
  AppointmentTag(value: 'tour_360', label: 'Tour 360º', tone: _info),
  AppointmentTag(value: 'keys', label: 'Chaves', tone: _warning),
  AppointmentTag(value: 'signage', label: 'Placa', tone: _warning),
  AppointmentTag(value: 'documents', label: 'Documentos', tone: _slate),
  AppointmentTag(
      value: 'client_transport', label: 'Levar cliente', tone: _success),
  AppointmentTag(value: 'measurement', label: 'Medição', tone: _slate),
  AppointmentTag(
      value: 'owner_present', label: 'Proprietário presente', tone: _success),
];

AppointmentTag? appointmentTagByValue(String value) {
  for (final t in kAppointmentTags) {
    if (t.value == value) return t;
  }
  return null;
}
