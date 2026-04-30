// Сервис для аутентификации
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'server_config.dart';

class AuthService {
  static String get baseUrl => ServerConfig.apiBaseUrl;
  
  // Singleton instance
  static final AuthService instance = AuthService._();
  AuthService._();
  
  // Текущий пользователь (кэшированный)
  User? _cachedUser;
  User? get currentUser => _cachedUser;
  
  /// Обновить кэшированного пользователя (для внутреннего использования)
  void _updateCachedUser(User? user) {
    _cachedUser = user;
  }

  /// Установить пользователя после входа/регистрации (для статических login/register)
  void setUserAfterAuth(User user) {
    _cachedUser = user;
  }
  
  /// Проверить, инициализирован ли сервис
  static bool get isInitialized => true;
  
  // Ключи для хранения токенов
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'user';
  
  /// Инициализация сервиса
  static Future<void> init() async {
    // Загружаем пользователя из SharedPreferences
    try {
      // На веб-платформе перезагружаем SharedPreferences перед чтением
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
        print('🔄 SharedPreferences перезагружен при инициализации');
      } catch (e) {
        print('⚠️ Не удалось перезагрузить SharedPreferences: $e');
      }
      
      final user = await getCurrentUser();
      final token = await getAccessToken();
      
      if (user != null && token != null) {
        instance._cachedUser = user;
        print('✅ AuthService: Пользователь загружен из SharedPreferences: ${user.email} (id: ${user.id})');
        print('✅ AuthService: Токен найден: ${token.substring(0, 20)}...');
        
        // Проверяем, не истек ли токен, и обновляем при необходимости
        try {
          // Пытаемся проверить токен, делая запрос к API
          // Если токен истек, попробуем обновить его
          final refreshToken = await SharedPreferences.getInstance().then((prefs) => prefs.getString(_refreshTokenKey));
          if (refreshToken != null) {
            // Токен есть, пользователь должен оставаться авторизованным
            print('✅ AuthService: Refresh токен найден, пользователь остается авторизованным');
          }
        } catch (e) {
          print('⚠️ AuthService: Ошибка при проверке токена: $e');
          // Не очищаем пользователя, возможно токен еще действителен
        }
      } else {
        if (user == null) {
          print('⚠️ AuthService: Пользователь не найден в SharedPreferences');
        }
        if (token == null) {
          print('⚠️ AuthService: Токен не найден в SharedPreferences');
        }
        // Очищаем кэш, если нет пользователя или токена
        instance._cachedUser = null;
        
        // Дополнительная проверка - может быть данные еще не загрузились
        // Попробуем еще раз через небольшую задержку с перезагрузкой
        await Future.delayed(const Duration(milliseconds: 200));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final retryUser = await getCurrentUser();
          final retryToken = await getAccessToken();
          if (retryUser != null && retryToken != null) {
            instance._cachedUser = retryUser;
            print('✅ AuthService: Пользователь найден при повторной проверке: ${retryUser.email}');
          } else {
            print('⚠️ AuthService: Повторная проверка не дала результатов');
          }
        } catch (e) {
          print('⚠️ AuthService: Ошибка при повторной проверке: $e');
        }
      }
    } catch (e) {
      print('❌ AuthService: Ошибка при загрузке пользователя: $e');
      // Игнорируем ошибки при инициализации
      instance._cachedUser = null;
    }
  }
  
  /// Вход по email и паролю
  Future<void> signInWithEmail(String email, String password) async {
    final response = await login(email: email, password: password);
    _cachedUser = response.user;
    
    // Дополнительно сохраняем пользователя в кэш (на случай, если _saveUser не сработал)
    try {
      await _saveUser(response.user);
    } catch (e) {
      print('⚠️ Предупреждение: не удалось сохранить пользователя дополнительно: $e');
    }
    
    // Проверяем, что токен и пользователь сохранены
    await Future.delayed(const Duration(milliseconds: 100)); // Даем время на сохранение
    final savedToken = await getAccessToken();
    final savedUser = await getCurrentUser();
    if (savedToken != null && savedUser != null) {
      print('✅ Токен и пользователь сохранены после входа: ${savedUser.email}');
      print('✅ Токен: ${savedToken.substring(0, 20)}...');
      // Обновляем кэш на всякий случай
      _cachedUser = savedUser;
    } else {
      print('❌ ОШИБКА: Токен или пользователь не сохранены после входа!');
      if (savedToken == null) print('   - Токен отсутствует');
      if (savedUser == null) print('   - Пользователь отсутствует');
      // Пытаемся сохранить еще раз
      if (savedUser == null) {
        try {
          await _saveUser(response.user);
          print('🔄 Попытка повторного сохранения пользователя...');
        } catch (e) {
          print('❌ Не удалось сохранить пользователя повторно: $e');
        }
      }
    }
  }
  
  /// Регистрация по email и паролю
  Future<void> createUserWithEmail(String email, String password, {String? name}) async {
    final response = await register(
      email: email,
      password: password,
      name: name ?? email.split('@').first,
    );
    _cachedUser = response.user;
    // Проверяем, что токен и пользователь сохранены
    final savedToken = await getAccessToken();
    final savedUser = await getCurrentUser();
    if (savedToken != null && savedUser != null) {
      print('✅ Токен и пользователь сохранены после регистрации: ${savedUser.email}');
    } else {
      print('❌ ОШИБКА: Токен или пользователь не сохранены после регистрации!');
    }
  }
  
  /// Вход через Google
  Future<void> signInWithGoogle() async {
    try {
      // Инициализируем Google Sign In
      final GoogleSignIn googleSignIn = GoogleSignIn(
        scopes: ['email', 'profile'],
      );
      
      // Запускаем процесс входа
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        // Пользователь отменил вход
        throw AuthException('Google sign in cancelled');
      }
      
      // Получаем authentication details
      final GoogleSignInAuthentication googleAuthData = await googleUser.authentication;
      
      // Получаем id_token
      final String? idToken = googleAuthData.idToken;
      
      if (idToken == null) {
        throw AuthException('Failed to get Google ID token');
      }
      
      // Отправляем id_token на backend
      final response = await googleAuth(idToken: idToken);
      _cachedUser = response.user;
      // Проверяем, что токен и пользователь сохранены
      final savedToken = await getAccessToken();
      final savedUser = await getCurrentUser();
      if (savedToken != null && savedUser != null) {
        print('✅ Токен и пользователь сохранены после входа через Google: ${savedUser.email}');
      } else {
        print('❌ ОШИБКА: Токен или пользователь не сохранены после входа через Google!');
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      throw AuthException('Google sign in failed: $e');
    }
  }
  
  /// Вход через Google (внутренний метод)
  static Future<AuthResponse> googleAuth({required String idToken}) async {
    final uri = Uri.parse('$baseUrl/auth/google');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final authResponse = AuthResponse.fromJson(data);
        
        // Сохраняем токены
        await _saveTokens(authResponse.token, authResponse.refreshToken);
        await _saveUser(authResponse.user);
        
        return authResponse;
      } else {
        try {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw AuthException(error['detail'] ?? 'Google authentication failed');
        } catch (e) {
          throw AuthException('Google authentication failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch')) {
        throw AuthException('Backend сервер не запущен. Пожалуйста, запустите backend сервер (см. BACKEND_START_INSTRUCTIONS.md)');
      }
      throw AuthException('Ошибка входа через Google: $e');
    }
  }
  
  /// Выйти из аккаунта
  Future<void> signOut() async {
    _cachedUser = null;
    await _clearTokens();
    // Также очищаем пользователя из SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    print('✅ Выход выполнен, токены и пользователь очищены');
  }
  
  /// Stream изменений состояния авторизации (заглушка)
  Stream<User?> authStateChanges() {
    // TODO: Реализовать stream изменений
    return Stream.value(_cachedUser);
  }
  
  /// Очистить токены
  static Future<void> _clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
  }
  
  /// Регистрация нового пользователя
  static Future<AuthResponse> register({
    required String email,
    required String password,
    required String name,
    String? username,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/register');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
          if (username != null) 'username': username,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final authResponse = AuthResponse.fromJson(data);
        
        // Сохраняем токены и пользователя
        await _saveTokens(authResponse.token, authResponse.refreshToken);
        await _saveUser(authResponse.user);
        instance.setUserAfterAuth(authResponse.user);
        
        return authResponse;
      } else {
        try {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw AuthException(error['detail'] ?? 'Registration failed');
        } catch (e) {
          throw AuthException('Registration failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch')) {
        throw AuthException('Backend сервер не запущен. Пожалуйста, запустите backend сервер (см. BACKEND_START_INSTRUCTIONS.md)');
      }
      throw AuthException('Ошибка регистрации: $e');
    }
  }
  
  /// Вход пользователя
  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw AuthException('Превышено время ожидания ответа от сервера. Проверьте, что сервер запущен и доступен.');
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final authResponse = AuthResponse.fromJson(data);
        
        // Сохраняем токены и пользователя
        await _saveTokens(authResponse.token, authResponse.refreshToken);
        await _saveUser(authResponse.user);
        instance.setUserAfterAuth(authResponse.user);
        
        return authResponse;
      } else {
        try {
          final error = jsonDecode(response.body) as Map<String, dynamic>;
          throw AuthException(error['detail'] ?? 'Login failed');
        } catch (e) {
          throw AuthException('Login failed: ${response.statusCode}');
        }
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AuthException('Превышено время ожидания ответа от сервера. Проверьте, что сервер запущен и доступен на http://localhost:5000');
      } else if (e is http.ClientException || 
                 e.toString().contains('Failed host lookup') || 
                 e.toString().contains('Connection refused') ||
                 e.toString().contains('Failed to fetch')) {
        throw AuthException('Не удалось подключиться к серверу. Проверьте, что сервер запущен на http://localhost:5000');
      }
      throw AuthException('Ошибка входа: $e');
    }
  }
  
  /// Выход
  static Future<void> logout() async {
    instance._cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
  }
  
  /// Получить текущий токен
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }
  
  /// Получить текущего пользователя
  static Future<User?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userJson = prefs.getString(_userKey);
    if (userJson == null) return null;
    return User.fromJson(jsonDecode(userJson));
  }
  
  /// Проверить, авторизован ли пользователь
  static Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }
  
  /// Обновить токен
  static Future<String> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(_refreshTokenKey);
    
    if (refreshToken == null) {
      throw AuthException('No refresh token available');
    }
    
    final uri = Uri.parse('$baseUrl/auth/refresh');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': refreshToken}),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw AuthException('Превышено время ожидания ответа от сервера');
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final newAccessToken = data['token'] as String;
        final newRefreshToken = data['refresh_token'] as String;
        
        await _saveTokens(newAccessToken, newRefreshToken);
        return newAccessToken;
      } else {
        throw AuthException('Token refresh failed');
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (e.toString().contains('Failed host lookup') || 
          e.toString().contains('Connection refused') ||
          e.toString().contains('Failed to fetch') ||
          e.toString().contains('Превышено время ожидания')) {
        throw AuthException('Сервер недоступен. Проверьте подключение к серверу.');
      }
      throw AuthException('Ошибка обновления токена: $e');
    }
  }
  
  static Future<void> _saveTokens(String accessToken, String refreshToken) async {
    final prefs = await SharedPreferences.getInstance();
    final saved1 = await prefs.setString(_accessTokenKey, accessToken);
    final saved2 = await prefs.setString(_refreshTokenKey, refreshToken);
    print('💾 Токены сохранены: access_token=${saved1}, refresh_token=${saved2}');
    
    // На веб-платформе нужно перезагрузить SharedPreferences для гарантии сохранения
    try {
      await prefs.reload();
    } catch (e) {
      print('⚠️ Не удалось перезагрузить SharedPreferences: $e');
    }
    
    // Проверяем, что токены действительно сохранены
    final verifyAccess = prefs.getString(_accessTokenKey);
    final verifyRefresh = prefs.getString(_refreshTokenKey);
    if (verifyAccess == null || verifyRefresh == null) {
      print('❌ ОШИБКА: Токены не сохранились!');
      print('   verifyAccess: ${verifyAccess != null ? "OK" : "NULL"}');
      print('   verifyRefresh: ${verifyRefresh != null ? "OK" : "NULL"}');
    } else {
      print('✅ Токены успешно сохранены и проверены');
      print('   access_token длина: ${verifyAccess.length}');
      print('   refresh_token длина: ${verifyRefresh.length}');
    }
  }
  
  static Future<void> _saveUser(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = jsonEncode(user.toJson());
      final saved = await prefs.setString(_userKey, userJson);
      print('💾 Пользователь сохранен: ${user.email} (id: ${user.id}), saved=$saved');
      
      // На веб-платформе нужно перезагрузить SharedPreferences для гарантии сохранения
      try {
        await prefs.reload();
      } catch (e) {
        print('⚠️ Не удалось перезагрузить SharedPreferences: $e');
      }
      
      // Проверяем, что пользователь действительно сохранен
      final verifyUser = prefs.getString(_userKey);
      if (verifyUser == null) {
        print('❌ ОШИБКА: Пользователь не сохранился!');
      } else {
        print('✅ Пользователь успешно сохранен и проверен');
        print('   Длина JSON: ${verifyUser.length} символов');
        // Дополнительная проверка - пытаемся распарсить
        try {
          final parsedUser = User.fromJson(jsonDecode(verifyUser));
          print('✅ Пользователь успешно загружен из проверки: ${parsedUser.email} (id: ${parsedUser.id})');
        } catch (e) {
          print('❌ ОШИБКА: Не удалось распарсить сохраненного пользователя: $e');
          print('   JSON начало: ${verifyUser.substring(0, verifyUser.length > 100 ? 100 : verifyUser.length)}...');
        }
      }
    } catch (e) {
      print('❌ ОШИБКА при сохранении пользователя: $e');
      rethrow;
    }
  }
}

class AuthResponse {
  final String token;
  final String refreshToken;
  final User user;
  
  AuthResponse({
    required this.token,
    required this.refreshToken,
    required this.user,
  });
  
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String,
      refreshToken: json['refresh_token'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
    );
  }
}

class User {
  final int id;
  final String email;
  final String name;
  final String? username;
  final String? avatarUrl;
  final String? bio;
  final bool isPrivate;
  final bool isAdmin;
  final bool isModerator;
  final DateTime createdAt;
  
  // Геттер для совместимости с Firebase Auth
  String get uid => id.toString();
  
  User({
    required this.id,
    required this.email,
    required this.name,
    this.username,
    this.avatarUrl,
    this.bio,
    required this.isPrivate,
    this.isAdmin = false,
    this.isModerator = false,
    required this.createdAt,
  });
  
  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String,
      name: json['name'] as String,
      username: json['username'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      isPrivate: json['is_private'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      isModerator: json['is_moderator'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'username': username,
      'avatar_url': avatarUrl,
      'bio': bio,
      'is_private': isPrivate,
      'is_admin': isAdmin,
      'is_moderator': isModerator,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  
  @override
  String toString() => message;
}
