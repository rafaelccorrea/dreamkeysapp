import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Modelo de endereço retornado pela API de CEP
class CepAddress {
  final String cep;
  final String? street;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? complement;

  CepAddress({
    required this.cep,
    this.street,
    this.neighborhood,
    this.city,
    this.state,
    this.complement,
  });

  factory CepAddress.fromJson(Map<String, dynamic> json) {
    return CepAddress(
      cep: json['cep']?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '',
      street: json['logradouro']?.toString() ?? json['street']?.toString(),
      neighborhood: json['bairro']?.toString() ?? json['neighborhood']?.toString(),
      city: json['localidade']?.toString() ?? json['city']?.toString(),
      state: json['uf']?.toString() ?? json['state']?.toString(),
      complement: json['complemento']?.toString() ?? json['complement']?.toString(),
    );
  }
}

/// Serviço de busca de CEP
class CepService {
  CepService._();

  static final CepService instance = CepService._();

  /// Busca endereço por CEP usando ViaCEP (API pública)
  Future<CepAddress?> searchCep(String cep) async {
    // Remove formatação do CEP
    final cleanCep = cep.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (cleanCep.length != 8) {
      debugPrint('❌ [CEP_SERVICE] CEP inválido: $cep');
      return null;
    }

    debugPrint('🔍 [CEP_SERVICE] Buscando CEP: $cleanCep');

    try {
      final uri = Uri.parse('https://viacep.com.br/ws/$cleanCep/json/');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body) as Map<String, dynamic>;
        
        // ViaCEP retorna erro quando CEP não encontrado
        if (jsonData.containsKey('erro')) {
          debugPrint('❌ [CEP_SERVICE] CEP não encontrado: $cleanCep');
          return null;
        }

        final address = CepAddress.fromJson(jsonData);
        debugPrint('✅ [CEP_SERVICE] CEP encontrado: ${address.city} - ${address.state}');
        return address;
      }

      debugPrint('❌ [CEP_SERVICE] Erro HTTP: ${response.statusCode}');
      return null;
    } catch (e) {
      debugPrint('❌ [CEP_SERVICE] Erro de conexão: $e');
      return null;
    }
  }
}





