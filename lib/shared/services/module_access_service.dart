import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'permission_service.dart';
import 'company_service.dart';
import 'secure_storage_service.dart';

/// Informações sobre um módulo
class ModuleInfo {
  final String id;
  final String name;
  final String description;
  final String icon;
  final String route;
  final List<String> requiredPermissions;
  final String category;

  ModuleInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.route,
    required this.requiredPermissions,
    required this.category,
  });
}

/// Serviço unificado para gerenciar permissões e módulos
/// Similar ao useModuleAccess do React
class ModuleAccessService {
  ModuleAccessService._();

  static final ModuleAccessService instance = ModuleAccessService._();

  MyPermissionsResponse? _userPermissions;
  Company? _selectedCompany;
  String? _userRole;
  bool _isLoading = false;

  /// Estado de carregamento
  bool get isLoading => _isLoading;

  /// Permissões do usuário
  MyPermissionsResponse? get userPermissions => _userPermissions;

  /// Empresa selecionada
  Company? get selectedCompany => _selectedCompany;

  /// Role do usuário
  String? get userRole => _userRole;

  /// Lista de nomes de permissões do usuário
  List<String> get userPermissionNames =>
      _userPermissions?.permissionNames ?? [];

  /// Módulos disponíveis na empresa
  List<String> get companyModules => _selectedCompany?.availableModules ?? [];

  /// Inicializa o serviço carregando permissões e empresa
  Future<void> initialize() async {
    try {
      _isLoading = true;
      debugPrint('🔄 [MODULE_ACCESS] Inicializando serviço...');

      // Carregar permissões
      final permissionService = PermissionService.instance;
      final companyId = await SecureStorageService.instance.getCompanyId();
      final userId = await _getCurrentUserId();

      if (userId != null && companyId != null) {
        // Verificar cache primeiro
        final cacheValid = await permissionService.isCacheValid(
          currentCompanyId: companyId,
          currentUserId: userId,
        );

        if (cacheValid) {
          final cache = await permissionService.getPermissionsCache();
          if (cache != null) {
            _userPermissions = MyPermissionsResponse(
              userId: userId,
              userName: '',
              userEmail: '',
              permissions: [],
              permissionNames: List<String>.from(cache['permissions'] as List? ?? []),
            );
            _userRole = cache['role']?.toString();
            debugPrint('✅ [MODULE_ACCESS] Permissões carregadas do cache');
          }
        }

        // Se não tem cache válido, carregar da API
        if (_userPermissions == null) {
          final response = await permissionService.getMyPermissions();
          if (response.success && response.data != null) {
            _userPermissions = response.data!;
            _userRole = _userPermissions!.permissionNames.isNotEmpty
                ? await _getUserRole()
                : null;
          }
        }
      }

      // Carregar empresa selecionada
      if (companyId != null) {
        final companyResponse = await CompanyService.instance.getCompanyById(companyId);
        if (companyResponse.success && companyResponse.data != null) {
          _selectedCompany = companyResponse.data!;
          debugPrint('✅ [MODULE_ACCESS] Empresa carregada: ${_selectedCompany!.name}');
        }
      }

      debugPrint('✅ [MODULE_ACCESS] Serviço inicializado');
    } catch (e, stackTrace) {
      debugPrint('❌ [MODULE_ACCESS] Erro ao inicializar: $e');
      debugPrint('📚 [MODULE_ACCESS] StackTrace: $stackTrace');
    } finally {
      _isLoading = false;
    }
  }

  /// Atualiza permissões manualmente
  Future<void> refreshPermissions() async {
    try {
      _isLoading = true;
      final permissionService = PermissionService.instance;
      final response = await permissionService.getMyPermissions();

      if (response.success && response.data != null) {
        _userPermissions = response.data!;
        _userRole = await _getUserRole();
        debugPrint('✅ [MODULE_ACCESS] Permissões atualizadas');
      }
    } catch (e) {
      debugPrint('❌ [MODULE_ACCESS] Erro ao atualizar permissões: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Atualiza empresa selecionada
  Future<void> refreshCompany() async {
    try {
      final companyId = await SecureStorageService.instance.getCompanyId();
      if (companyId != null) {
        final companyResponse = await CompanyService.instance.getCompanyById(companyId);
        if (companyResponse.success && companyResponse.data != null) {
          _selectedCompany = companyResponse.data!;
          debugPrint('✅ [MODULE_ACCESS] Empresa atualizada');
        }
      }
    } catch (e) {
      debugPrint('❌ [MODULE_ACCESS] Erro ao atualizar empresa: $e');
    }
  }

  /// Verifica se usuário tem uma permissão específica
  bool hasPermission(String permission) {
    if (_hasRoleBypass()) return true;
    return _userPermissions?.permissionNames.contains(permission) ?? false;
  }

  /// Verifica se usuário tem qualquer uma das permissões
  bool hasAnyPermission(List<String> permissions) {
    if (_hasRoleBypass()) return true;
    if (_userPermissions == null) return false;
    return permissions.any((p) => _userPermissions!.permissionNames.contains(p));
  }

  /// Verifica se usuário tem todas as permissões
  bool hasAllPermissions(List<String> permissions) {
    if (_hasRoleBypass()) return true;
    if (_userPermissions == null) return false;
    return permissions.every((p) => _userPermissions!.permissionNames.contains(p));
  }

  /// Verifica se módulo está disponível na empresa
  bool isModuleAvailableForCompany(String moduleId) {
    if (_hasRoleBypass()) return true;
    return _selectedCompany?.availableModules.contains(moduleId) ?? false;
  }

  /// Verifica se usuário tem permissões para o módulo
  bool hasPermissionForModule(String moduleId) {
    if (_hasRoleBypass()) return true;
    
    final requiredPermissions = _getRequiredPermissionsForModule(moduleId);
    if (requiredPermissions.isEmpty) return true;
    
    return hasAnyPermission(requiredPermissions);
  }

  /// Verifica se pode acessar uma rota específica
  bool canAccessRoutePath(String route) {
    final moduleId = _getModuleIdFromRoute(route);
    if (moduleId == null) return true;
    
    return isModuleAvailableForCompany(moduleId) && hasPermissionForModule(moduleId);
  }

  /// Limpa dados do serviço
  void clear() {
    _userPermissions = null;
    _selectedCompany = null;
    _userRole = null;
    _isLoading = false;
    debugPrint('🧹 [MODULE_ACCESS] Dados limpos');
  }

  /// Verifica se role tem bypass
  bool _hasRoleBypass() {
    final role = _userRole?.toLowerCase();
    return role == 'master' || role == 'admin' || role == 'manager';
  }

  /// Obtém ID do usuário atual
  Future<String?> _getCurrentUserId() async {
    try {
      // Tentar obter do token JWT ou de outra fonte
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        // Decodificar JWT para obter userId
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          final decoded = _decodeBase64(payload);
          final json = _parseJson(decoded);
          return json['sub']?.toString() ?? json['userId']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [MODULE_ACCESS] Erro ao obter userId: $e');
      return null;
    }
  }

  /// Obtém role do usuário
  Future<String?> _getUserRole() async {
    try {
      final token = await SecureStorageService.instance.getAccessToken();
      if (token != null) {
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = parts[1];
          final decoded = _decodeBase64(payload);
          final json = _parseJson(decoded);
          return json['role']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('⚠️ [MODULE_ACCESS] Erro ao obter role: $e');
      return null;
    }
  }

  /// Decodifica base64
  String _decodeBase64(String str) {
    try {
      String output = str.replaceAll('-', '+').replaceAll('_', '/');
      switch (output.length % 4) {
        case 0:
          break;
        case 2:
          output += '==';
          break;
        case 3:
          output += '=';
          break;
      }
      return String.fromCharCodes(base64Decode(output));
    } catch (e) {
      return '';
    }
  }

  /// Parse JSON
  Map<String, dynamic> _parseJson(String jsonString) {
    try {
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      return {};
    }
  }

  /// Obtém permissões necessárias para um módulo
  List<String> _getRequiredPermissionsForModule(String moduleId) {
    final mapping = PermissionModuleMapping.getRequiredPermissions(moduleId);
    return mapping;
  }

  /// Obtém módulo ID de uma rota
  String? _getModuleIdFromRoute(String route) {
    return PermissionModuleMapping.getModuleFromRoute(route);
  }
}

/// Mapeamento de permissões para módulos
class PermissionModuleMapping {
  /// Mapeamento de permissão para módulo
  static final Map<String, String> _permissionToModule = {
    // Property permissions
    'property:view': 'property_management',
    'property:create': 'property_management',
    'property:update': 'property_management',
    'property:delete': 'property_management',
    'property:export': 'property_management',
    
    // Client permissions
    'client:view': 'client_management',
    'client:create': 'client_management',
    'client:update': 'client_management',
    'client:delete': 'client_management',
    
    // Kanban permissions
    'kanban:view': 'kanban_management',
    'kanban:create': 'kanban_management',
    'kanban:update': 'kanban_management',
    'kanban:delete': 'kanban_management',
    
    // Inspection permissions
    'inspection:view': 'vistoria',
    'inspection:create': 'vistoria',
    'inspection:update': 'vistoria',
    'inspection:delete': 'vistoria',
    
    // Key permissions
    'key:view': 'key_control',
    'key:create': 'key_control',
    'key:update': 'key_control',
    'key:delete': 'key_control',
    
    // Rental permissions
    'rental:view': 'rental_management',
    'rental:create': 'rental_management',
    'rental:update': 'rental_management',
    'rental:delete': 'rental_management',
    
    // Calendar permissions
    'calendar:view': 'calendar_management',
    'calendar:create': 'calendar_management',
    'calendar:update': 'calendar_management',
    'calendar:delete': 'calendar_management',
    
    // Commission permissions
    'commission:view': 'commission_management',
    'commission:create': 'commission_management',
    'commission:update': 'commission_management',
    'commission:delete': 'commission_management',
    
    // Match permissions
    'match:view': 'match_system',
    'match:create': 'match_system',
    'match:update': 'match_system',
    'match:delete': 'match_system',
    
    // Team permissions
    'team:view': 'team_management',
    'team:create': 'team_management',
    'team:update': 'team_management',
    'team:delete': 'team_management',
    
    // Financial permissions
    'financial:view': 'financial_management',
    'financial:create': 'financial_management',
    'financial:update': 'financial_management',
    'financial:delete': 'financial_management',
    
    // Marketing permissions
    'marketing:view': 'marketing_tools',
    'marketing:create': 'marketing_tools',
    'marketing:update': 'marketing_tools',
    'marketing:delete': 'marketing_tools',
    
    // BI permissions
    'bi:view': 'business_intelligence',
    'bi:create': 'business_intelligence',
    'bi:update': 'business_intelligence',
    'bi:delete': 'business_intelligence',
    
    // Gamification permissions
    'gamification:view': 'gamification',
    'gamification:create': 'gamification',
    'gamification:update': 'gamification',
    'gamification:delete': 'gamification',
  };

  /// Mapeamento de rota para módulo
  static final Map<String, String> _routeToModule = {
    '/properties': 'property_management',
    '/clients': 'client_management',
    '/kanban': 'kanban_management',
    '/inspection': 'vistoria',
    '/vistoria': 'vistoria',
    '/keys': 'key_control',
    '/rentals': 'rental_management',
    '/calendar': 'calendar_management',
    '/commissions': 'commission_management',
    '/matches': 'match_system',
    '/teams': 'team_management',
    '/financial': 'financial_management',
    '/marketing': 'marketing_tools',
    '/bi': 'business_intelligence',
    '/dashboard': 'dashboard',
  };

  /// Permissões necessárias por módulo
  static final Map<String, List<String>> _moduleRequiredPermissions = {
    'property_management': ['property:view'],
    'client_management': ['client:view'],
    'kanban_management': ['kanban:view'],
    'vistoria': ['inspection:view'],
    'key_control': ['key:view'],
    'rental_management': ['rental:view'],
    'calendar_management': ['calendar:view'],
    'commission_management': ['commission:view'],
    'match_system': ['match:view'],
    'team_management': ['team:view'],
    'financial_management': ['financial:view'],
    'marketing_tools': ['marketing:view'],
    'business_intelligence': ['bi:view'],
    'gamification': ['gamification:view'],
  };

  /// Obtém módulo necessário para uma permissão
  static String? getRequiredModuleForPermission(String permission) {
    return _permissionToModule[permission];
  }

  /// Obtém módulo de uma rota
  static String? getModuleFromRoute(String route) {
    // Verificar rota exata primeiro
    if (_routeToModule.containsKey(route)) {
      return _routeToModule[route];
    }
    
    // Verificar se rota começa com algum padrão
    for (final entry in _routeToModule.entries) {
      if (route.startsWith(entry.key)) {
        return entry.value;
      }
    }
    
    return null;
  }

  /// Obtém permissões necessárias para um módulo
  static List<String> getRequiredPermissions(String moduleId) {
    return _moduleRequiredPermissions[moduleId] ?? [];
  }
}

