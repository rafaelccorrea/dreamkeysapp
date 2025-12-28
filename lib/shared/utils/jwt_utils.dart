import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Utilitário para trabalhar com tokens JWT
class JwtUtils {
  JwtUtils._();

  /// Decodifica um token JWT e retorna o payload
  static Map<String, dynamic>? decodeToken(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) {
        debugPrint('⚠️ [JWT] Token inválido: não possui 3 partes');
        return null;
      }

      // Decodificar o payload (segunda parte)
      final payload = parts[1];
      
      // Adicionar padding se necessário
      var normalizedPayload = payload;
      switch (payload.length % 4) {
        case 1:
          normalizedPayload += '===';
          break;
        case 2:
          normalizedPayload += '==';
          break;
        case 3:
          normalizedPayload += '=';
          break;
      }

      final decodedBytes = base64Url.decode(normalizedPayload);
      final decodedString = utf8.decode(decodedBytes);
      final payloadMap = jsonDecode(decodedString) as Map<String, dynamic>;

      return payloadMap;
    } catch (e) {
      debugPrint('❌ [JWT] Erro ao decodificar token: $e');
      return null;
    }
  }

  /// Obtém o tempo de expiração (exp) do token em segundos
  static int? getExpirationTime(String token) {
    final payload = decodeToken(token);
    if (payload == null) return null;

    final exp = payload['exp'];
    if (exp == null) {
      debugPrint('⚠️ [JWT] Token não possui campo "exp"');
      return null;
    }

    if (exp is int) {
      return exp;
    } else if (exp is double) {
      return exp.toInt();
    }

    return null;
  }

  /// Verifica se o token está expirado
  static bool isTokenExpired(String token) {
    final exp = getExpirationTime(token);
    if (exp == null) return true;

    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return currentTime >= exp;
  }

  /// Calcula quantos segundos faltam para o token expirar
  /// Retorna null se não conseguir calcular
  static int? getTimeUntilExpiry(String token) {
    final exp = getExpirationTime(token);
    if (exp == null) return null;

    final currentTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final timeUntilExpiry = exp - currentTime;

    return timeUntilExpiry > 0 ? timeUntilExpiry : 0;
  }

  /// Verifica se o token expira em menos de X minutos
  static bool expiresInLessThan(String token, int minutes) {
    final timeUntilExpiry = getTimeUntilExpiry(token);
    if (timeUntilExpiry == null) return true;

    final secondsThreshold = minutes * 60;
    return timeUntilExpiry < secondsThreshold && timeUntilExpiry > 0;
  }

  /// Verifica se o token é válido (não expirado)
  static bool isTokenValid(String token) {
    return !isTokenExpired(token);
  }
}









