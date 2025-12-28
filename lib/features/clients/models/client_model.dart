import 'package:flutter/foundation.dart';

/// Modelos de dados para Clientes

/// Tipos de Cliente
enum ClientType {
  buyer('buyer', 'Comprador'),
  seller('seller', 'Vendedor'),
  renter('renter', 'Locatário'),
  lessor('lessor', 'Locador'),
  investor('investor', 'Investidor'),
  general('general', 'Geral');

  final String value;
  final String label;

  const ClientType(this.value, this.label);

  static ClientType fromString(String? value) {
    if (value == null) return general;
    return ClientType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => general,
    );
  }
}

/// Status do Cliente
enum ClientStatus {
  active('active', 'Ativo'),
  inactive('inactive', 'Inativo'),
  contacted('contacted', 'Contatado'),
  interested('interested', 'Interessado'),
  closed('closed', 'Fechado');

  final String value;
  final String label;

  const ClientStatus(this.value, this.label);

  static ClientStatus fromString(String? value) {
    if (value == null) return active;
    return ClientStatus.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => active,
    );
  }
}

/// Estado Civil
enum MaritalStatus {
  single('single', 'Solteiro(a)'),
  married('married', 'Casado(a)'),
  divorced('divorced', 'Divorciado(a)'),
  widowed('widowed', 'Viúvo(a)'),
  separated('separated', 'Separado(a)'),
  commonLaw('common_law', 'União Estável');

  final String value;
  final String label;

  const MaritalStatus(this.value, this.label);

  static MaritalStatus? fromString(String? value) {
    if (value == null) return null;
    try {
      return MaritalStatus.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Situação Profissional
enum EmploymentStatus {
  employed('employed', 'Empregado'),
  unemployed('unemployed', 'Desempregado'),
  retired('retired', 'Aposentado'),
  selfEmployed('self_employed', 'Autônomo'),
  student('student', 'Estudante'),
  freelancer('freelancer', 'Freelancer');

  final String value;
  final String label;

  const EmploymentStatus(this.value, this.label);

  static EmploymentStatus? fromString(String? value) {
    if (value == null) return null;
    try {
      return EmploymentStatus.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Origem do Lead
enum ClientSource {
  whatsapp('whatsapp', 'WhatsApp'),
  socialMedia('social_media', 'Redes Sociais'),
  phone('phone', 'Telefone'),
  olx('olx', 'OLX'),
  zapImoveis('zap_imoveis', 'Zap Imóveis'),
  vivaReal('viva_real', 'Viva Real'),
  dreamKeys('dream_keys', 'Dream Keys'),
  other('other', 'Outro');

  final String value;
  final String label;

  const ClientSource(this.value, this.label);

  static ClientSource? fromString(String? value) {
    if (value == null) return null;
    try {
      return ClientSource.values.firstWhere(
        (e) => e.value == value.toLowerCase(),
      );
    } catch (e) {
      return null;
    }
  }
}

/// Modelo de Cônjuge
class Spouse {
  final String id;
  final String name;
  final String? cpf;
  final String? phone;
  final String? email;
  final String? birthDate;
  final String? rg;
  final String createdAt;
  final String updatedAt;

  Spouse({
    required this.id,
    required this.name,
    this.cpf,
    this.phone,
    this.email,
    this.birthDate,
    this.rg,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Spouse.fromJson(Map<String, dynamic> json) {
    return Spouse(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      cpf: json['cpf']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      birthDate:
          json['birthDate']?.toString() ?? json['birth_date']?.toString(),
      rg: json['rg']?.toString(),
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt:
          json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (cpf != null) 'cpf': cpf,
      if (phone != null) 'phone': phone,
      if (email != null) 'email': email,
      if (birthDate != null) 'birthDate': birthDate,
      if (rg != null) 'rg': rg,
    };
  }
}

/// Modelo de Cliente
class Client {
  final String id;
  final String name;
  final String email;
  final String cpf;
  final String phone;
  final String? secondaryPhone;
  final String? whatsapp;
  final String? birthDate;
  final String? anniversaryDate;
  final String? rg;
  final String zipCode;
  final String address;
  final String city;
  final String state;
  final String neighborhood;
  final ClientType type;
  final ClientStatus status;
  final MaritalStatus? maritalStatus;
  final bool? hasDependents;
  final int? numberOfDependents;
  final String? dependentsNotes;
  final EmploymentStatus? employmentStatus;
  final String? companyName;
  final String? jobPosition;
  final String? jobStartDate;
  final String? jobEndDate;
  final bool? isCurrentlyWorking;
  final int? companyTimeMonths;
  final String? contractType;
  final bool? isRetired;
  final double? monthlyIncome;
  final double? grossSalary;
  final double? netSalary;
  final double? thirteenthSalary;
  final double? vacationPay;
  final String? otherIncomeSources;
  final double? otherIncomeAmount;
  final double? familyIncome;
  final int? creditScore;
  final String? lastCreditCheck;
  final String? bankName;
  final String? bankAgency;
  final String? accountType;
  final bool? hasProperty;
  final bool? hasVehicle;
  final String? referenceName;
  final String? referencePhone;
  final String? referenceRelationship;
  final String? professionalReferenceName;
  final String? professionalReferencePhone;
  final String? professionalReferencePosition;
  final String? incomeRange;
  final String? loanRange;
  final String? priceRange;
  final String? preferences;
  final String? notes;
  final String? preferredContactMethod;
  final String? preferredPropertyType;
  final String? preferredCity;
  final String? preferredNeighborhood;
  final double? minArea;
  final double? maxArea;
  final int? minBedrooms;
  final int? maxBedrooms;
  final int? minBathrooms;
  final double? minValue;
  final double? maxValue;
  final Map<String, dynamic>? desiredFeatures;
  final bool isActive;
  final String companyId;
  final String responsibleUserId;
  final UserInfo? responsibleUser;
  final String? capturedById;
  final UserInfo? capturedBy;
  final Spouse? spouse;
  final ClientSource? leadSource;
  final bool? mcmvInterested;
  final bool? mcmvEligible;
  final String? mcmvIncomeRange;
  final String? mcmvCadunicoNumber;
  final String? mcmvPreRegistrationDate;
  final String createdAt;
  final String updatedAt;

  Client({
    required this.id,
    required this.name,
    required this.email,
    required this.cpf,
    required this.phone,
    this.secondaryPhone,
    this.whatsapp,
    this.birthDate,
    this.anniversaryDate,
    this.rg,
    required this.zipCode,
    required this.address,
    required this.city,
    required this.state,
    required this.neighborhood,
    required this.type,
    required this.status,
    this.maritalStatus,
    this.hasDependents,
    this.numberOfDependents,
    this.dependentsNotes,
    this.employmentStatus,
    this.companyName,
    this.jobPosition,
    this.jobStartDate,
    this.jobEndDate,
    this.isCurrentlyWorking,
    this.companyTimeMonths,
    this.contractType,
    this.isRetired,
    this.monthlyIncome,
    this.grossSalary,
    this.netSalary,
    this.thirteenthSalary,
    this.vacationPay,
    this.otherIncomeSources,
    this.otherIncomeAmount,
    this.familyIncome,
    this.creditScore,
    this.lastCreditCheck,
    this.bankName,
    this.bankAgency,
    this.accountType,
    this.hasProperty,
    this.hasVehicle,
    this.referenceName,
    this.referencePhone,
    this.referenceRelationship,
    this.professionalReferenceName,
    this.professionalReferencePhone,
    this.professionalReferencePosition,
    this.incomeRange,
    this.loanRange,
    this.priceRange,
    this.preferences,
    this.notes,
    this.preferredContactMethod,
    this.preferredPropertyType,
    this.preferredCity,
    this.preferredNeighborhood,
    this.minArea,
    this.maxArea,
    this.minBedrooms,
    this.maxBedrooms,
    this.minBathrooms,
    this.minValue,
    this.maxValue,
    this.desiredFeatures,
    required this.isActive,
    required this.companyId,
    required this.responsibleUserId,
    this.responsibleUser,
    this.capturedById,
    this.capturedBy,
    this.spouse,
    this.leadSource,
    this.mcmvInterested,
    this.mcmvEligible,
    this.mcmvIncomeRange,
    this.mcmvCadunicoNumber,
    this.mcmvPreRegistrationDate,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Helper para converter valores numéricos que podem vir como string ou número
  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed;
    }
    return null;
  }

  /// Helper para converter valores inteiros que podem vir como string ou número
  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      return parsed;
    }
    return null;
  }

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      cpf: json['cpf']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      secondaryPhone:
          json['secondaryPhone']?.toString() ??
          json['secondary_phone']?.toString(),
      whatsapp: json['whatsapp']?.toString(),
      birthDate:
          json['birthDate']?.toString() ?? json['birth_date']?.toString(),
      anniversaryDate:
          json['anniversaryDate']?.toString() ??
          json['anniversary_date']?.toString(),
      rg: json['rg']?.toString(),
      zipCode:
          json['zipCode']?.toString() ?? json['zip_code']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      neighborhood: json['neighborhood']?.toString() ?? '',
      type: ClientType.fromString(json['type']?.toString()),
      status: ClientStatus.fromString(json['status']?.toString()),
      maritalStatus: MaritalStatus.fromString(
        json['maritalStatus']?.toString() ?? json['marital_status']?.toString(),
      ),
      hasDependents:
          json['hasDependents'] as bool? ?? json['has_dependents'] as bool?,
      numberOfDependents: _parseInt(
        json['numberOfDependents'] ?? json['number_of_dependents'],
      ),
      dependentsNotes:
          json['dependentsNotes']?.toString() ??
          json['dependents_notes']?.toString(),
      employmentStatus: EmploymentStatus.fromString(
        json['employmentStatus']?.toString() ??
            json['employment_status']?.toString(),
      ),
      companyName:
          json['companyName']?.toString() ?? json['company_name']?.toString(),
      jobPosition:
          json['jobPosition']?.toString() ?? json['job_position']?.toString(),
      jobStartDate:
          json['jobStartDate']?.toString() ??
          json['job_start_date']?.toString(),
      jobEndDate:
          json['jobEndDate']?.toString() ?? json['job_end_date']?.toString(),
      isCurrentlyWorking:
          json['isCurrentlyWorking'] as bool? ??
          json['is_currently_working'] as bool?,
      companyTimeMonths: _parseInt(
        json['companyTimeMonths'] ?? json['company_time_months'],
      ),
      contractType:
          json['contractType']?.toString() ?? json['contract_type']?.toString(),
      isRetired: json['isRetired'] as bool? ?? json['is_retired'] as bool?,
      monthlyIncome: _parseDouble(
        json['monthlyIncome'] ?? json['monthly_income'],
      ),
      grossSalary: _parseDouble(json['grossSalary'] ?? json['gross_salary']),
      netSalary: _parseDouble(json['netSalary'] ?? json['net_salary']),
      thirteenthSalary: _parseDouble(
        json['thirteenthSalary'] ?? json['thirteenth_salary'],
      ),
      vacationPay: _parseDouble(json['vacationPay'] ?? json['vacation_pay']),
      otherIncomeSources:
          json['otherIncomeSources']?.toString() ??
          json['other_income_sources']?.toString(),
      otherIncomeAmount: _parseDouble(
        json['otherIncomeAmount'] ?? json['other_income_amount'],
      ),
      familyIncome: _parseDouble(json['familyIncome'] ?? json['family_income']),
      creditScore: _parseInt(json['creditScore'] ?? json['credit_score']),
      lastCreditCheck:
          json['lastCreditCheck']?.toString() ??
          json['last_credit_check']?.toString(),
      bankName: json['bankName']?.toString() ?? json['bank_name']?.toString(),
      bankAgency:
          json['bankAgency']?.toString() ?? json['bank_agency']?.toString(),
      accountType:
          json['accountType']?.toString() ?? json['account_type']?.toString(),
      hasProperty:
          json['hasProperty'] as bool? ?? json['has_property'] as bool?,
      hasVehicle: json['hasVehicle'] as bool? ?? json['has_vehicle'] as bool?,
      referenceName:
          json['referenceName']?.toString() ??
          json['reference_name']?.toString(),
      referencePhone:
          json['referencePhone']?.toString() ??
          json['reference_phone']?.toString(),
      referenceRelationship:
          json['referenceRelationship']?.toString() ??
          json['reference_relationship']?.toString(),
      professionalReferenceName:
          json['professionalReferenceName']?.toString() ??
          json['professional_reference_name']?.toString(),
      professionalReferencePhone:
          json['professionalReferencePhone']?.toString() ??
          json['professional_reference_phone']?.toString(),
      professionalReferencePosition:
          json['professionalReferencePosition']?.toString() ??
          json['professional_reference_position']?.toString(),
      incomeRange:
          json['incomeRange']?.toString() ?? json['income_range']?.toString(),
      loanRange:
          json['loanRange']?.toString() ?? json['loan_range']?.toString(),
      priceRange:
          json['priceRange']?.toString() ?? json['price_range']?.toString(),
      preferences: json['preferences']?.toString(),
      notes: json['notes']?.toString(),
      preferredContactMethod:
          json['preferredContactMethod']?.toString() ??
          json['preferred_contact_method']?.toString(),
      preferredPropertyType:
          json['preferredPropertyType']?.toString() ??
          json['preferred_property_type']?.toString(),
      preferredCity:
          json['preferredCity']?.toString() ??
          json['preferred_city']?.toString(),
      preferredNeighborhood:
          json['preferredNeighborhood']?.toString() ??
          json['preferred_neighborhood']?.toString(),
      minArea: _parseDouble(json['minArea'] ?? json['min_area']),
      maxArea: _parseDouble(json['maxArea'] ?? json['max_area']),
      minBedrooms: _parseInt(json['minBedrooms'] ?? json['min_bedrooms']),
      maxBedrooms: _parseInt(json['maxBedrooms'] ?? json['max_bedrooms']),
      minBathrooms: _parseInt(json['minBathrooms'] ?? json['min_bathrooms']),
      minValue: _parseDouble(json['minValue'] ?? json['min_value']),
      maxValue: _parseDouble(json['maxValue'] ?? json['max_value']),
      desiredFeatures:
          json['desiredFeatures'] as Map<String, dynamic>? ??
          json['desired_features'] as Map<String, dynamic>?,
      isActive: json['isActive'] as bool? ?? json['is_active'] as bool? ?? true,
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      responsibleUserId:
          json['responsibleUserId']?.toString() ??
          json['responsible_user_id']?.toString() ??
          '',
      responsibleUser: json['responsibleUser'] != null
          ? UserInfo.fromJson(json['responsibleUser'] as Map<String, dynamic>)
          : json['responsible_user'] != null
          ? UserInfo.fromJson(json['responsible_user'] as Map<String, dynamic>)
          : null,
      capturedById:
          json['capturedById']?.toString() ??
          json['captured_by_id']?.toString(),
      capturedBy: json['capturedBy'] != null
          ? UserInfo.fromJson(json['capturedBy'] as Map<String, dynamic>)
          : json['captured_by'] != null
          ? UserInfo.fromJson(json['captured_by'] as Map<String, dynamic>)
          : null,
      spouse: json['spouse'] != null
          ? Spouse.fromJson(json['spouse'] as Map<String, dynamic>)
          : null,
      leadSource: ClientSource.fromString(
        json['leadSource']?.toString() ?? json['lead_source']?.toString(),
      ),
      mcmvInterested:
          json['mcmvInterested'] as bool? ?? json['mcmv_interested'] as bool?,
      mcmvEligible:
          json['mcmvEligible'] as bool? ?? json['mcmv_eligible'] as bool?,
      mcmvIncomeRange:
          json['mcmvIncomeRange']?.toString() ??
          json['mcmv_income_range']?.toString(),
      mcmvCadunicoNumber:
          json['mcmvCadunicoNumber']?.toString() ??
          json['mcmv_cadunico_number']?.toString(),
      mcmvPreRegistrationDate:
          json['mcmvPreRegistrationDate']?.toString() ??
          json['mcmv_pre_registration_date']?.toString(),
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt:
          json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'cpf': cpf,
      'phone': phone,
      if (secondaryPhone != null) 'secondaryPhone': secondaryPhone,
      if (whatsapp != null) 'whatsapp': whatsapp,
      if (birthDate != null) 'birthDate': birthDate,
      if (anniversaryDate != null) 'anniversaryDate': anniversaryDate,
      if (rg != null) 'rg': rg,
      'zipCode': zipCode,
      'address': address,
      'city': city,
      'state': state,
      'neighborhood': neighborhood,
      'type': type.value,
      'status': status.value,
      if (maritalStatus != null) 'maritalStatus': maritalStatus!.value,
      if (hasDependents != null) 'hasDependents': hasDependents,
      if (numberOfDependents != null) 'numberOfDependents': numberOfDependents,
      if (dependentsNotes != null) 'dependentsNotes': dependentsNotes,
      if (employmentStatus != null) 'employmentStatus': employmentStatus!.value,
      if (companyName != null) 'companyName': companyName,
      if (jobPosition != null) 'jobPosition': jobPosition,
      if (jobStartDate != null) 'jobStartDate': jobStartDate,
      if (jobEndDate != null) 'jobEndDate': jobEndDate,
      if (isCurrentlyWorking != null) 'isCurrentlyWorking': isCurrentlyWorking,
      if (companyTimeMonths != null) 'companyTimeMonths': companyTimeMonths,
      if (contractType != null) 'contractType': contractType,
      if (isRetired != null) 'isRetired': isRetired,
      if (monthlyIncome != null) 'monthlyIncome': monthlyIncome,
      if (grossSalary != null) 'grossSalary': grossSalary,
      if (netSalary != null) 'netSalary': netSalary,
      if (thirteenthSalary != null) 'thirteenthSalary': thirteenthSalary,
      if (vacationPay != null) 'vacationPay': vacationPay,
      if (otherIncomeSources != null) 'otherIncomeSources': otherIncomeSources,
      if (otherIncomeAmount != null) 'otherIncomeAmount': otherIncomeAmount,
      if (familyIncome != null) 'familyIncome': familyIncome,
      if (creditScore != null) 'creditScore': creditScore,
      if (lastCreditCheck != null) 'lastCreditCheck': lastCreditCheck,
      if (bankName != null) 'bankName': bankName,
      if (bankAgency != null) 'bankAgency': bankAgency,
      if (accountType != null) 'accountType': accountType,
      if (hasProperty != null) 'hasProperty': hasProperty,
      if (hasVehicle != null) 'hasVehicle': hasVehicle,
      if (referenceName != null) 'referenceName': referenceName,
      if (referencePhone != null) 'referencePhone': referencePhone,
      if (referenceRelationship != null)
        'referenceRelationship': referenceRelationship,
      if (professionalReferenceName != null)
        'professionalReferenceName': professionalReferenceName,
      if (professionalReferencePhone != null)
        'professionalReferencePhone': professionalReferencePhone,
      if (professionalReferencePosition != null)
        'professionalReferencePosition': professionalReferencePosition,
      if (incomeRange != null) 'incomeRange': incomeRange,
      if (loanRange != null) 'loanRange': loanRange,
      if (priceRange != null) 'priceRange': priceRange,
      if (preferences != null) 'preferences': preferences,
      if (notes != null) 'notes': notes,
      if (preferredContactMethod != null)
        'preferredContactMethod': preferredContactMethod,
      if (preferredPropertyType != null)
        'preferredPropertyType': preferredPropertyType,
      if (preferredCity != null) 'preferredCity': preferredCity,
      if (preferredNeighborhood != null)
        'preferredNeighborhood': preferredNeighborhood,
      if (minArea != null) 'minArea': minArea,
      if (maxArea != null) 'maxArea': maxArea,
      if (minBedrooms != null) 'minBedrooms': minBedrooms,
      if (maxBedrooms != null) 'maxBedrooms': maxBedrooms,
      if (minBathrooms != null) 'minBathrooms': minBathrooms,
      if (minValue != null) 'minValue': minValue,
      if (maxValue != null) 'maxValue': maxValue,
      if (desiredFeatures != null) 'desiredFeatures': desiredFeatures,
      if (leadSource != null) 'leadSource': leadSource!.value,
      if (mcmvInterested != null) 'mcmvInterested': mcmvInterested,
      if (mcmvEligible != null) 'mcmvEligible': mcmvEligible,
      if (mcmvIncomeRange != null) 'mcmvIncomeRange': mcmvIncomeRange,
      if (mcmvCadunicoNumber != null) 'mcmvCadunicoNumber': mcmvCadunicoNumber,
      if (mcmvPreRegistrationDate != null)
        'mcmvPreRegistrationDate': mcmvPreRegistrationDate,
    };
  }
}

/// Informações básicas de usuário
class UserInfo {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatar;

  UserInfo({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatar,
  });

  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      avatar: json['avatar']?.toString(),
    );
  }
}

/// DTO para criar cliente
class CreateClientDto {
  final String name;
  final String email;
  final String cpf;
  final String phone;
  final String zipCode;
  final String address;
  final String city;
  final String state;
  final String neighborhood;
  final ClientType type;
  final String capturedById;
  final ClientStatus? status;
  final String? secondaryPhone;
  final String? whatsapp;
  final String? birthDate;
  final String? anniversaryDate;
  final String? rg;
  final MaritalStatus? maritalStatus;
  final bool? hasDependents;
  final int? numberOfDependents;
  final String? dependentsNotes;
  final EmploymentStatus? employmentStatus;
  final String? companyName;
  final String? jobPosition;
  final String? jobStartDate;
  final String? jobEndDate;
  final bool? isCurrentlyWorking;
  final int? companyTimeMonths;
  final String? contractType;
  final bool? isRetired;
  final double? monthlyIncome;
  final double? grossSalary;
  final double? netSalary;
  final double? thirteenthSalary;
  final double? vacationPay;
  final String? otherIncomeSources;
  final double? otherIncomeAmount;
  final double? familyIncome;
  final int? creditScore;
  final String? lastCreditCheck;
  final String? bankName;
  final String? bankAgency;
  final String? accountType;
  final bool? hasProperty;
  final bool? hasVehicle;
  final String? referenceName;
  final String? referencePhone;
  final String? referenceRelationship;
  final String? professionalReferenceName;
  final String? professionalReferencePhone;
  final String? professionalReferencePosition;
  final String? incomeRange;
  final String? loanRange;
  final String? priceRange;
  final String? preferences;
  final String? notes;
  final String? preferredContactMethod;
  final String? preferredPropertyType;
  final String? preferredCity;
  final String? preferredNeighborhood;
  final double? minArea;
  final double? maxArea;
  final int? minBedrooms;
  final int? maxBedrooms;
  final int? minBathrooms;
  final double? minValue;
  final double? maxValue;
  final Map<String, dynamic>? desiredFeatures;
  final ClientSource? leadSource;
  final bool? mcmvInterested;
  final bool? mcmvEligible;
  final String? mcmvIncomeRange;
  final String? mcmvCadunicoNumber;
  final String? mcmvPreRegistrationDate;

  CreateClientDto({
    required this.name,
    required this.email,
    required this.cpf,
    required this.phone,
    required this.zipCode,
    required this.address,
    required this.city,
    required this.state,
    required this.neighborhood,
    required this.type,
    required this.capturedById,
    this.status,
    this.secondaryPhone,
    this.whatsapp,
    this.birthDate,
    this.anniversaryDate,
    this.rg,
    this.maritalStatus,
    this.hasDependents,
    this.numberOfDependents,
    this.dependentsNotes,
    this.employmentStatus,
    this.companyName,
    this.jobPosition,
    this.jobStartDate,
    this.jobEndDate,
    this.isCurrentlyWorking,
    this.companyTimeMonths,
    this.contractType,
    this.isRetired,
    this.monthlyIncome,
    this.grossSalary,
    this.netSalary,
    this.thirteenthSalary,
    this.vacationPay,
    this.otherIncomeSources,
    this.otherIncomeAmount,
    this.familyIncome,
    this.creditScore,
    this.lastCreditCheck,
    this.bankName,
    this.bankAgency,
    this.accountType,
    this.hasProperty,
    this.hasVehicle,
    this.referenceName,
    this.referencePhone,
    this.referenceRelationship,
    this.professionalReferenceName,
    this.professionalReferencePhone,
    this.professionalReferencePosition,
    this.incomeRange,
    this.loanRange,
    this.priceRange,
    this.preferences,
    this.notes,
    this.preferredContactMethod,
    this.preferredPropertyType,
    this.preferredCity,
    this.preferredNeighborhood,
    this.minArea,
    this.maxArea,
    this.minBedrooms,
    this.maxBedrooms,
    this.minBathrooms,
    this.minValue,
    this.maxValue,
    this.desiredFeatures,
    this.leadSource,
    this.mcmvInterested,
    this.mcmvEligible,
    this.mcmvIncomeRange,
    this.mcmvCadunicoNumber,
    this.mcmvPreRegistrationDate,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'email': email,
      'cpf': cpf,
      'phone': phone,
      'zipCode': zipCode,
      'address': address,
      'city': city,
      'state': state,
      'neighborhood': neighborhood,
      'type': type.value,
      'capturedById': capturedById,
      if (status != null) 'status': status!.value,
      if (secondaryPhone != null) 'secondaryPhone': secondaryPhone,
      if (whatsapp != null) 'whatsapp': whatsapp,
      if (birthDate != null) 'birthDate': birthDate,
      if (anniversaryDate != null) 'anniversaryDate': anniversaryDate,
      if (rg != null) 'rg': rg,
      if (maritalStatus != null) 'maritalStatus': maritalStatus!.value,
      if (hasDependents != null) 'hasDependents': hasDependents,
      if (numberOfDependents != null) 'numberOfDependents': numberOfDependents,
      if (dependentsNotes != null) 'dependentsNotes': dependentsNotes,
      if (employmentStatus != null) 'employmentStatus': employmentStatus!.value,
      if (companyName != null) 'companyName': companyName,
      if (jobPosition != null) 'jobPosition': jobPosition,
      if (jobStartDate != null) 'jobStartDate': jobStartDate,
      if (jobEndDate != null) 'jobEndDate': jobEndDate,
      if (isCurrentlyWorking != null) 'isCurrentlyWorking': isCurrentlyWorking,
      if (companyTimeMonths != null) 'companyTimeMonths': companyTimeMonths,
      if (contractType != null) 'contractType': contractType,
      if (isRetired != null) 'isRetired': isRetired,
      if (monthlyIncome != null) 'monthlyIncome': monthlyIncome,
      if (grossSalary != null) 'grossSalary': grossSalary,
      if (netSalary != null) 'netSalary': netSalary,
      if (thirteenthSalary != null) 'thirteenthSalary': thirteenthSalary,
      if (vacationPay != null) 'vacationPay': vacationPay,
      if (otherIncomeSources != null) 'otherIncomeSources': otherIncomeSources,
      if (otherIncomeAmount != null) 'otherIncomeAmount': otherIncomeAmount,
      if (familyIncome != null) 'familyIncome': familyIncome,
      if (creditScore != null) 'creditScore': creditScore,
      if (lastCreditCheck != null) 'lastCreditCheck': lastCreditCheck,
      if (bankName != null) 'bankName': bankName,
      if (bankAgency != null) 'bankAgency': bankAgency,
      if (accountType != null) 'accountType': accountType,
      if (hasProperty != null) 'hasProperty': hasProperty,
      if (hasVehicle != null) 'hasVehicle': hasVehicle,
      if (referenceName != null) 'referenceName': referenceName,
      if (referencePhone != null) 'referencePhone': referencePhone,
      if (referenceRelationship != null)
        'referenceRelationship': referenceRelationship,
      if (professionalReferenceName != null)
        'professionalReferenceName': professionalReferenceName,
      if (professionalReferencePhone != null)
        'professionalReferencePhone': professionalReferencePhone,
      if (professionalReferencePosition != null)
        'professionalReferencePosition': professionalReferencePosition,
      if (incomeRange != null) 'incomeRange': incomeRange,
      if (loanRange != null) 'loanRange': loanRange,
      if (priceRange != null) 'priceRange': priceRange,
      if (preferences != null) 'preferences': preferences,
      if (notes != null) 'notes': notes,
      if (preferredContactMethod != null)
        'preferredContactMethod': preferredContactMethod,
      if (preferredPropertyType != null)
        'preferredPropertyType': preferredPropertyType,
      if (preferredCity != null) 'preferredCity': preferredCity,
      if (preferredNeighborhood != null)
        'preferredNeighborhood': preferredNeighborhood,
      if (minArea != null) 'minArea': minArea,
      if (maxArea != null) 'maxArea': maxArea,
      if (minBedrooms != null) 'minBedrooms': minBedrooms,
      if (maxBedrooms != null) 'maxBedrooms': maxBedrooms,
      if (minBathrooms != null) 'minBathrooms': minBathrooms,
      if (minValue != null) 'minValue': minValue,
      if (maxValue != null) 'maxValue': maxValue,
      if (desiredFeatures != null) 'desiredFeatures': desiredFeatures,
      if (leadSource != null) 'leadSource': leadSource!.value,
      if (mcmvInterested != null) 'mcmvInterested': mcmvInterested,
      if (mcmvEligible != null) 'mcmvEligible': mcmvEligible,
      if (mcmvIncomeRange != null) 'mcmvIncomeRange': mcmvIncomeRange,
      if (mcmvCadunicoNumber != null) 'mcmvCadunicoNumber': mcmvCadunicoNumber,
      if (mcmvPreRegistrationDate != null)
        'mcmvPreRegistrationDate': mcmvPreRegistrationDate,
    };
  }
}

/// DTO para atualizar cliente
class UpdateClientDto extends CreateClientDto {
  UpdateClientDto({
    required super.name,
    required super.email,
    required super.cpf,
    required super.phone,
    required super.zipCode,
    required super.address,
    required super.city,
    required super.state,
    required super.neighborhood,
    required super.type,
    required super.capturedById,
    super.status,
    super.secondaryPhone,
    super.whatsapp,
    super.birthDate,
    super.anniversaryDate,
    super.rg,
    super.maritalStatus,
    super.hasDependents,
    super.numberOfDependents,
    super.dependentsNotes,
    super.employmentStatus,
    super.companyName,
    super.jobPosition,
    super.jobStartDate,
    super.jobEndDate,
    super.isCurrentlyWorking,
    super.companyTimeMonths,
    super.contractType,
    super.isRetired,
    super.monthlyIncome,
    super.grossSalary,
    super.netSalary,
    super.thirteenthSalary,
    super.vacationPay,
    super.otherIncomeSources,
    super.otherIncomeAmount,
    super.familyIncome,
    super.creditScore,
    super.lastCreditCheck,
    super.bankName,
    super.bankAgency,
    super.accountType,
    super.hasProperty,
    super.hasVehicle,
    super.referenceName,
    super.referencePhone,
    super.referenceRelationship,
    super.professionalReferenceName,
    super.professionalReferencePhone,
    super.professionalReferencePosition,
    super.incomeRange,
    super.loanRange,
    super.priceRange,
    super.preferences,
    super.notes,
    super.preferredContactMethod,
    super.preferredPropertyType,
    super.preferredCity,
    super.preferredNeighborhood,
    super.minArea,
    super.maxArea,
    super.minBedrooms,
    super.maxBedrooms,
    super.minBathrooms,
    super.minValue,
    super.maxValue,
    super.desiredFeatures,
    super.leadSource,
    super.mcmvInterested,
    super.mcmvEligible,
    super.mcmvIncomeRange,
    super.mcmvCadunicoNumber,
    super.mcmvPreRegistrationDate,
  });
}

/// Filtros de busca de clientes
class ClientSearchFilters {
  final String? name;
  final String? email;
  final String? phone;
  final String? search;
  final String? document;
  final String? city;
  final String? neighborhood;
  final String? state;
  final ClientType? type;
  final ClientStatus? status;
  final String? responsibleUserId;
  final bool? isActive;
  final bool? onlyMyData;
  final String? createdFrom;
  final String? createdTo;
  final int? limit;
  final int? page;
  final String? sortBy;
  final String? sortOrder;

  ClientSearchFilters({
    this.name,
    this.email,
    this.phone,
    this.search,
    this.document,
    this.city,
    this.neighborhood,
    this.state,
    this.type,
    this.status,
    this.responsibleUserId,
    this.isActive,
    this.onlyMyData,
    this.createdFrom,
    this.createdTo,
    this.limit,
    this.page,
    this.sortBy,
    this.sortOrder,
  });

  Map<String, String> toQueryParams() {
    final params = <String, String>{};
    if (name != null && name!.isNotEmpty) params['name'] = name!;
    if (email != null && email!.isNotEmpty) params['email'] = email!;
    if (phone != null && phone!.isNotEmpty) params['phone'] = phone!;
    if (search != null && search!.isNotEmpty) params['search'] = search!;
    if (document != null && document!.isNotEmpty)
      params['document'] = document!;
    if (city != null && city!.isNotEmpty) params['city'] = city!;
    if (neighborhood != null && neighborhood!.isNotEmpty)
      params['neighborhood'] = neighborhood!;
    if (state != null && state!.isNotEmpty) params['state'] = state!;
    if (type != null) params['type'] = type!.value;
    if (status != null) params['status'] = status!.value;
    if (responsibleUserId != null && responsibleUserId!.isNotEmpty)
      params['responsibleUserId'] = responsibleUserId!;
    if (isActive != null) params['isActive'] = isActive.toString();
    if (onlyMyData != null) params['onlyMyData'] = onlyMyData.toString();
    if (createdFrom != null && createdFrom!.isNotEmpty)
      params['createdFrom'] = createdFrom!;
    if (createdTo != null && createdTo!.isNotEmpty)
      params['createdTo'] = createdTo!;
    if (limit != null) params['limit'] = limit.toString();
    if (page != null) params['page'] = page.toString();
    if (sortBy != null && sortBy!.isNotEmpty) params['sortBy'] = sortBy!;
    if (sortOrder != null && sortOrder!.isNotEmpty)
      params['sortOrder'] = sortOrder!;
    return params;
  }
}

/// Estatísticas de clientes
class ClientStatistics {
  final int activeClients;
  final int totalClients;
  final int buyers;
  final int sellers;
  final int renters;
  final int lessors;
  final int investors;
  final int generalClients;

  ClientStatistics({
    required this.activeClients,
    required this.totalClients,
    required this.buyers,
    required this.sellers,
    required this.renters,
    required this.lessors,
    required this.investors,
    required this.generalClients,
  });

  factory ClientStatistics.fromJson(Map<String, dynamic> json) {
    return ClientStatistics(
      activeClients: json['active_clients'] as int? ?? 0,
      totalClients: json['total_clients'] as int? ?? 0,
      buyers: json['buyers'] as int? ?? 0,
      sellers: json['sellers'] as int? ?? 0,
      renters: json['renters'] as int? ?? 0,
      lessors: json['lessors'] as int? ?? 0,
      investors: json['investors'] as int? ?? 0,
      generalClients: json['general_clients'] as int? ?? 0,
    );
  }
}

/// Resposta de listagem de clientes
class ClientListResponse {
  final List<Client> data;
  final PaginationInfo? pagination;

  ClientListResponse({required this.data, this.pagination});

  factory ClientListResponse.fromJson(Map<String, dynamic> json) {
    try {
      // Tentar extrair a lista de diferentes formas
      List<dynamic>? dataList;

      if (json['data'] != null) {
        if (json['data'] is List) {
          dataList = json['data'] as List<dynamic>;
        } else if (json['data'] is Map) {
          // Se 'data' for um Map, pode ter uma lista dentro
          final dataMap = json['data'] as Map<String, dynamic>;
          if (dataMap['data'] is List) {
            dataList = dataMap['data'] as List<dynamic>;
          } else if (dataMap['clients'] is List) {
            dataList = dataMap['clients'] as List<dynamic>;
          }
        }
      } else if (json['clients'] != null && json['clients'] is List) {
        dataList = json['clients'] as List<dynamic>;
      }

      // Se ainda não encontrou, tentar verificar se o próprio json é uma lista
      // (isso não deve acontecer aqui, mas por segurança)
      if (dataList == null) {
        dataList = [];
      }

      return ClientListResponse(
        data: dataList
            .map((e) {
              try {
                if (e is Map<String, dynamic>) {
                  return Client.fromJson(e);
                }
                return null;
              } catch (e) {
                debugPrint('❌ [CLIENT_MODEL] Erro ao parsear item: $e');
                return null;
              }
            })
            .whereType<Client>()
            .toList(),
        pagination: json['pagination'] != null
            ? PaginationInfo.fromJson(
                json['pagination'] as Map<String, dynamic>,
              )
            : null,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ [CLIENT_MODEL] Erro ao parsear ClientListResponse: $e');
      debugPrint('📚 [CLIENT_MODEL] StackTrace: $stackTrace');
      debugPrint('📚 [CLIENT_MODEL] JSON recebido: $json');
      return ClientListResponse(data: [], pagination: null);
    }
  }
}

/// Informações de paginação
class PaginationInfo {
  final int page;
  final int limit;
  final int total;
  final int totalPages;

  PaginationInfo({
    required this.page,
    required this.limit,
    required this.total,
    required this.totalPages,
  });

  factory PaginationInfo.fromJson(Map<String, dynamic> json) {
    return PaginationInfo(
      page: json['page'] as int? ?? 1,
      limit: json['limit'] as int? ?? 50,
      total: json['total'] as int? ?? 0,
      totalPages:
          json['totalPages'] as int? ?? json['total_pages'] as int? ?? 0,
    );
  }
}

/// Modelo de anexo para interações
class Attachment {
  final String id;
  final String? name;
  final String url;
  final String? mimeType;
  final int? size;

  Attachment({
    required this.id,
    this.name,
    required this.url,
    this.mimeType,
    this.size,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString(),
      url: json['url']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? json['mime_type']?.toString(),
      size: Client._parseInt(json['size']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'mimeType': mimeType,
      'size': size,
    };
  }
}

/// Modelo de interação com cliente
class ClientInteraction {
  final String id;
  final String clientId;
  final String companyId;
  final String createdById;
  final UserInfo? createdBy;
  final String? title;
  final String notes;
  final String? interactionAt;
  final List<Attachment> attachments;
  final String createdAt;
  final String updatedAt;

  ClientInteraction({
    required this.id,
    required this.clientId,
    required this.companyId,
    required this.createdById,
    this.createdBy,
    this.title,
    required this.notes,
    this.interactionAt,
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory ClientInteraction.fromJson(Map<String, dynamic> json) {
    List<Attachment> attachmentsList = [];
    if (json['attachments'] != null && json['attachments'] is List) {
      attachmentsList = (json['attachments'] as List<dynamic>)
          .map((e) {
            try {
              return Attachment.fromJson(e as Map<String, dynamic>);
            } catch (e) {
              return null;
            }
          })
          .whereType<Attachment>()
          .toList();
    }

    return ClientInteraction(
      id: json['id']?.toString() ?? '',
      clientId:
          json['clientId']?.toString() ?? json['client_id']?.toString() ?? '',
      companyId:
          json['companyId']?.toString() ?? json['company_id']?.toString() ?? '',
      createdById:
          json['createdById']?.toString() ??
          json['created_by_id']?.toString() ??
          '',
      createdBy: json['createdBy'] != null || json['created_by'] != null
          ? UserInfo.fromJson(
              (json['createdBy'] ?? json['created_by']) as Map<String, dynamic>,
            )
          : null,
      title: json['title']?.toString(),
      notes: json['notes']?.toString() ?? '',
      interactionAt:
          json['interactionAt']?.toString() ??
          json['interaction_at']?.toString(),
      attachments: attachmentsList,
      createdAt:
          json['createdAt']?.toString() ?? json['created_at']?.toString() ?? '',
      updatedAt:
          json['updatedAt']?.toString() ?? json['updated_at']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'clientId': clientId,
      'companyId': companyId,
      'createdById': createdById,
      'title': title,
      'notes': notes,
      'interactionAt': interactionAt,
      'attachments': attachments.map((a) => a.toJson()).toList(),
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
