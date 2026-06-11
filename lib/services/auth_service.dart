import 'package:flutter/foundation.dart';
// Сервис для аутентификации
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/config/google_auth_config.dart';
import '../core/network/haneat_http_client.dart';
import 'account_session_service.dart';
import 'server_config.dart';

bool _apiUnreachable(Object e) {
  final s = e.toString();
  return s.contains('Failed host lookup') ||
      s.contains('Connection refused') ||
      s.contains('Failed to fetch') ||
      s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Network is unreachable') ||
      s.contains('No route to host') ||
      s.contains('Connection reset');
}

bool _isDefinitiveSessionLoss(AuthException e) {
  final m = e.message;
  return m.contains('Сессия истекла') ||
      m.contains('Token refresh failed') ||
      m.contains('No refresh token');
}

class AuthService {
  static String get baseUrl => ServerConfig.apiBaseUrl;

  /// Ошибка при отсутствии access token: не путаем офлайн/сеть с выходом из аккаунта.
  static AuthException tokenUnavailableException() {
    if (instance.currentUser != null) {
      return AuthException(
        'Сервер недоступен. Проверьте подключение к серверу.',
      );
    }
    return AuthException('Сессия истекла. Войдите снова.');
  }

  static final List<void Function(User?)> _sessionListeners = [];

  /// Смена входа/выхода — пересчёт redirect в [GoRouter].
  static final ValueNotifier<int> sessionRevision = ValueNotifier(0);

  /// Подписка на смену аккаунта (вход/выход). Не вызывается при обновлении профиля (PATCH /users/me).
  static void registerSessionListener(void Function(User?) listener) {
    _sessionListeners.add(listener);
  }

  static void unregisterSessionListener(void Function(User?) listener) {
    _sessionListeners.remove(listener);
  }

  static void _dispatchSessionChanged(User? user) {
    sessionRevision.value++;
    unawaited(AccountSessionService.applySessionChange(user));
    for (final listener in List<void Function(User?)>.from(_sessionListeners)) {
      try {
        listener(user);
      } catch (e, st) {
        debugPrint('AuthService session listener: $e\n$st');
      }
    }
  }

  // Singleton instance
  static final AuthService instance = AuthService._();
  AuthService._();

  static GoogleSignIn? _googleSignIn;

  static GoogleSignIn _googleSignInInstance() {
    try {
      GoogleAuthConfig.ensureConfigured();
    } on StateError catch (e) {
      throw AuthException(e.message);
    }
    final platformHint = GoogleAuthConfig.missingPlatformHint();
    if (platformHint != null) {
      throw AuthException(platformHint);
    }
    return _googleSignIn ??= GoogleSignIn(
      scopes: const ['email', 'profile'],
      clientId: GoogleAuthConfig.iosClientId,
      serverClientId: GoogleAuthConfig.webClientId,
    );
  }
  
  // Текущий пользователь (кэшированный)
  User? _cachedUser;
  User? get currentUser => _cachedUser;
  
  /// Обновить кэшированного пользователя (для внутреннего использования)
  void _updateCachedUser(User? user) {
    _cachedUser = user;
  }

  /// Установить пользователя после входа/регистрации (для статических login/register).
  /// [notifySessionListeners] — только при реальном входе; для PATCH профиля оставляйте false.
  void setUserAfterAuth(User user, {bool notifySessionListeners = false}) {
    _cachedUser = user;
    if (notifySessionListeners) {
      _dispatchSessionChanged(user);
    }
  }

  Future<void> updateStoredUser(User user) async {
    setUserAfterAuth(user, notifySessionListeners: true);
    await AuthService._saveUser(user);
  }

  /// Счётчик обновлений профиля (scan_credits и т.д.) — для перерисовки UI.
  static final ValueNotifier<int> profileVersion = ValueNotifier(0);

  /// После PATCH /users/me (аватар, имя): обновить кэш и SharedPreferences.
  static Future<void> persistUpdatedUser(User user) async {
    instance.setUserAfterAuth(user);
    await _saveUser(user);
    profileVersion.value++;
  }

  /// Привязать номер телефона — друзья из адресной книги смогут вас найти.
  static Future<void> linkPhone(String phone) async {
    final token = await getAccessTokenForApi();
    if (token == null) throw AuthException('Войдите в аккаунт');
    final uri = Uri.parse('$baseUrl/users/me/phone');
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'phone': phone}),
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      final detail = body?['detail'];
      throw AuthException(
        detail is String ? detail : 'Не удалось привязать номер',
      );
    }
    final user = instance.currentUser;
    if (user != null) {
      await persistUpdatedUser(user.copyWith(phoneLinked: true));
    }
  }
  
  /// Проверить, инициализирован ли сервис
  static bool get isInitialized => true;
  
  // Ключи для хранения токенов
  static const String _accessTokenKey = 'access_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _userKey = 'user';
  
  /// Инициализация сервиса
  /// [deferTokenRefresh] — не ждать сеть при старте (быстрый показ UI), refresh в фоне.
  static Future<void> init({bool deferTokenRefresh = false}) async {
    try {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.reload();
      } catch (e) {
        debugPrint('⚠️ Не удалось перезагрузить SharedPreferences: $e');
      }

      final user = await getCurrentUser();
      final token = await getAccessToken();

      if (user != null && token != null) {
        instance._cachedUser = user;
        AccountSessionService.restoreCachedUser(user);
        debugPrint(
          '✅ AuthService: сессия из кэша (${user.email}), deferRefresh=$deferTokenRefresh',
        );
        if (deferTokenRefresh) {
          unawaited(_refreshSessionOnStartup());
        } else {
          await _refreshSessionOnStartup();
        }
        return;
      }

      instance._cachedUser = null;
      if (!deferTokenRefresh) {
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.reload();
          final retryUser = await getCurrentUser();
          final retryToken = await getAccessToken();
          if (retryUser != null && retryToken != null) {
            instance._cachedUser = retryUser;
            AccountSessionService.restoreCachedUser(retryUser);
            await _refreshSessionOnStartup();
          }
        } catch (e) {
          debugPrint('⚠️ AuthService: повторная проверка: $e');
        }
      }
    } catch (e) {
      debugPrint('❌ AuthService: Ошибка при загрузке пользователя: $e');
      instance._cachedUser = null;
    }
  }

  static Future<void> _refreshSessionOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasAccess = prefs.getString(_accessTokenKey)?.isNotEmpty == true;
      final hasRefresh = prefs.getString(_refreshTokenKey)?.isNotEmpty == true;
      if (!hasAccess && !hasRefresh) {
        if (instance._cachedUser != null) {
          debugPrint(
            '⚠️ AuthService: токены недоступны, остаёмся в аккаунте (кэш)',
          );
          return;
        }
        debugPrint('⚠️ AuthService: нет токенов и сессии — выход');
        await logout();
        return;
      }

      final fresh = await getAccessTokenForApi();
      if (fresh == null || fresh.isEmpty) {
        debugPrint(
          '⚠️ AuthService: access token недоступен, остаёмся в аккаунте (офлайн/сеть)',
        );
      }
    } on AuthException catch (e) {
      if (_isDefinitiveSessionLoss(e)) {
        debugPrint('⚠️ AuthService: сессия недействительна: $e');
        await logout();
      } else {
        debugPrint('⚠️ AuthService: refresh (сеть?), сессия сохранена: $e');
      }
    } catch (e) {
      debugPrint('⚠️ AuthService: refresh при init: $e');
    }
  }
  
  /// Вход по email и паролю
  Future<void> signInWithEmail(String email, String password) async {
    final response = await login(email: email, password: password);
    // login() уже сохранил токены и вызвал session change; синхронизируем кэш.
    setUserAfterAuth(response.user, notifySessionListeners: false);
    try {
      await _saveUser(response.user);
    } catch (e) {
      debugPrint('⚠️ Предупреждение: не удалось сохранить пользователя дополнительно: $e');
    }
  }
  
  /// Регистрация по email и паролю
  Future<void> createUserWithEmail(
    String email,
    String password, {
    String? name,
    required bool acceptLegal,
  }) async {
    final response = await register(
      email: email,
      password: password,
      name: name ?? email.split('@').first,
      acceptLegal: acceptLegal,
    );
    setUserAfterAuth(response.user, notifySessionListeners: false);
  }
  
  /// Вход через Google
  Future<void> signInWithGoogle({bool acceptLegal = false}) async {
    try {
      final GoogleSignIn googleSignIn = _googleSignInInstance();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      
      if (googleUser == null) {
        // Пользователь отменил вход
        throw AuthException('Вход через Google отменён');
      }
      
      // Получаем authentication details
      final GoogleSignInAuthentication googleAuthData = await googleUser.authentication;
      
      // Получаем id_token
      final String? idToken = googleAuthData.idToken;
      
      if (idToken == null) {
        throw AuthException('Не удалось получить токен Google');
      }
      
      // Отправляем id_token на backend
      final response = await googleAuth(
        idToken: idToken,
        acceptLegal: acceptLegal,
      );
      setUserAfterAuth(response.user, notifySessionListeners: true);
      // Проверяем, что токен и пользователь сохранены
      final savedToken = await getAccessToken();
      final savedUser = await getCurrentUser();
      if (savedToken != null && savedUser != null) {
        debugPrint('✅ Токен и пользователь сохранены после входа через Google: ${savedUser.email}');
      } else {
        debugPrint('❌ ОШИБКА: Токен или пользователь не сохранены после входа через Google!');
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      throw AuthException('Не удалось войти через Google');
    }
  }
  
  /// Вход через Google (внутренний метод)
  static Future<AuthResponse> googleAuth({
    required String idToken,
    bool acceptLegal = false,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/google');
    try {
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id_token': idToken,
          'accept_legal': acceptLegal,
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
          throw AuthException(error['detail']?.toString() ?? 'Ошибка входа через Google');
        } catch (e) {
          throw AuthException('Ошибка входа через Google (${response.statusCode})');
        }
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (_apiUnreachable(e)) {
        throw AuthException('Сервер недоступен. Проверьте подключение к интернету.');
      }
      throw AuthException('Ошибка входа через Google: $e');
    }
  }
  
  /// Выйти из аккаунта
  Future<void> signOut() async {
    _cachedUser = null;
    try {
      await _googleSignIn?.signOut();
    } catch (e) {
      debugPrint('Google signOut: $e');
    }
    await _clearTokens();
    // Также очищаем пользователя из SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    // Совпадает с PushNotificationService — после входа FCM снова уйдёт на сервер.
    await prefs.remove('fcm_token');
    debugPrint('✅ Выход выполнен, токены и пользователь очищены');
    _dispatchSessionChanged(null);
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
    required bool acceptLegal,
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
          'accept_legal': acceptLegal,
          if (username != null) 'username': username,
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final authResponse = AuthResponse.fromJson(data);
        
        // Сохраняем токены и пользователя
        await _saveTokens(authResponse.token, authResponse.refreshToken);
        await _saveUser(authResponse.user);
        instance.setUserAfterAuth(
          authResponse.user,
          notifySessionListeners: true,
        );

        return authResponse;
      } else {
        throw _authExceptionFromResponse(
          response,
          'Ошибка регистрации: ${response.statusCode}',
        );
      }
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (_apiUnreachable(e)) {
        throw AuthException('Сервер недоступен. Проверьте подключение к интернету.');
      }
      throw AuthException('Ошибка регистрации: $e');
    }
  }
  
  static const Duration _authRequestTimeout = Duration(seconds: 60);

  static AuthException _loginTimeoutException() => AuthException(
        'Сервер ${ServerConfig.apiBaseUrl} не ответил вовремя. '
        'Проверьте Wi‑Fi или мобильный интернет; отключите VPN и попробуйте снова.',
      );

  static AuthException _loginConnectionException() => AuthException(
        'Не удалось подключиться к ${ServerConfig.apiBaseUrl}. '
        'Проверьте интернет или попробуйте через Wi‑Fi.',
      );

  /// Вход пользователя
  static Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    if (kDebugMode) {
      debugPrint('🔐 POST $uri');
    }

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await _loginOnce(uri, email, password);
      } on AuthException catch (e) {
        lastError = e;
        final retryable = e.message.contains('время ожидания') ||
            e.message.contains('подключиться');
        if (attempt == 0 && retryable) {
          if (kDebugMode) debugPrint('🔐 login retry (${attempt + 2}/2)');
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
        if (attempt == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        throw _loginTimeoutException();
      } catch (e) {
        lastError = e;
        if (attempt == 0 &&
            (e is http.ClientException || _apiUnreachable(e))) {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          continue;
        }
        if (e is http.ClientException || _apiUnreachable(e)) {
          throw _loginConnectionException();
        }
        throw AuthException('Ошибка входа: $e');
      }
    }
    if (lastError is AuthException) throw lastError;
    throw _loginTimeoutException();
  }

  static Future<AuthResponse> _loginOnce(
    Uri uri,
    String email,
    String password,
  ) async {
    final response = await HanEatHttpClient.shared
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'password': password,
          }),
        )
        .timeout(
          _authRequestTimeout,
          onTimeout: () {
            throw _loginTimeoutException();
          },
        );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final authResponse = AuthResponse.fromJson(data);

      await _saveTokens(authResponse.token, authResponse.refreshToken);
      await _saveUser(authResponse.user);
      instance.setUserAfterAuth(
        authResponse.user,
        notifySessionListeners: true,
      );

      return authResponse;
    }
    throw _authExceptionFromResponse(
      response,
      'Ошибка входа: ${response.statusCode}',
    );
  }
  
  static Future<MessageResponse> forgotPassword({required String email}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/forgot-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось отправить письмо');
  }

  static Future<MessageResponse> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/reset-password'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token, 'new_password': newPassword}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось сменить пароль');
  }

  static Future<MessageResponse> verifyEmail({required String token}) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/verify-email'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось подтвердить email');
  }

  static Future<MessageResponse> resendVerification({String? email}) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final token = await getAccessTokenForApi();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/resend-verification'),
          headers: headers,
          body: jsonEncode({if (email != null) 'email': email.trim()}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(
      response,
      'Не удалось отправить письмо',
    );
  }

  static Future<MessageResponse> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = await getAccessTokenForApi();
    if (token == null) throw AuthException('Войдите в аккаунт');
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/change-password'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'current_password': currentPassword,
            'new_password': newPassword,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось сменить пароль');
  }

  static Future<MessageResponse> changeEmailRequest({
    required String newEmail,
    required String password,
  }) async {
    final token = await getAccessTokenForApi();
    if (token == null) throw AuthException('Войдите в аккаунт');
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/change-email'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'new_email': newEmail.trim(),
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось сменить email');
  }

  static Future<MessageResponse> confirmEmailChange({
    required String token,
  }) async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/auth/confirm-email-change'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'token': token}),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 200) {
      return MessageResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw _authExceptionFromResponse(response, 'Не удалось подтвердить email');
  }

  /// Выход
  static Future<void> logout() async {
    instance._cachedUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    await prefs.remove(_userKey);
    await prefs.remove('fcm_token');
    _dispatchSessionChanged(null);
  }
  
  /// Получить текущий токен
  static Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessTokenKey);
  }

  /// Декодирует payload JWT без проверки подписи (только [exp]).
  static bool _accessTokenLooksExpired(
    String token, {
    Duration skew = const Duration(seconds: 60),
  }) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return false;
      final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      return nowSec >= exp.toInt() - skew.inSeconds;
    } catch (_) {
      // Не считаем токен просроченным при ошибке decode — иначе лишний refresh/logout.
      return false;
    }
  }

  /// Access для запросов к API: при истёкшем JWT обновляет через refresh (если он есть).
  static Future<String?> getAccessTokenForApi() async {
    var token = await getAccessToken();
    if (token == null || token.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_refreshTokenKey) == null) {
        return null;
      }
      try {
        return await refreshToken();
      } on AuthException catch (e) {
        if (_isDefinitiveSessionLoss(e)) {
          await logout();
        } else {
          debugPrint('⚠️ getAccessTokenForApi: $e');
        }
        return null;
      }
    }
    if (!_accessTokenLooksExpired(token)) return token;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_refreshTokenKey) == null) {
        await logout();
        return null;
      }
      return await refreshToken();
    } on AuthException catch (e) {
      if (_isDefinitiveSessionLoss(e)) {
        await logout();
        return null;
      }
      debugPrint('⚠️ getAccessTokenForApi: $e');
      return _accessTokenLooksExpired(token) ? null : token;
    } catch (e) {
      debugPrint('⚠️ getAccessTokenForApi: refresh failed: $e');
      return _accessTokenLooksExpired(token) ? null : token;
    }
  }
  
  /// Получить текущего пользователя
  static Future<User?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = prefs.getString(_userKey);
      if (userJson == null) return null;
      return User.fromJson(jsonDecode(userJson) as Map<String, dynamic>);
    } catch (e, st) {
      debugPrint('getCurrentUser: повреждённые данные сессии, сброс: $e\n$st');
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_userKey);
      } catch (_) {}
      return null;
    }
  }
  
  /// Проверить, авторизован ли пользователь (есть пользователь и хотя бы один токен).
  static Future<bool> isAuthenticated() async {
    final user = await getCurrentUser();
    if (user == null) return false;
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString(_accessTokenKey);
    final refresh = prefs.getString(_refreshTokenKey);
    return (access != null && access.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
  }
  
  /// Один refresh за раз: бэкенд выдаёт новый refresh_token, параллельные
  /// запросы со старым токеном получали 401 и вызывали logout().
  static Future<String>? _refreshInFlight;

  /// Обновить токен
  static Future<String> refreshToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final future = _refreshTokenOnce();
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  static Future<String> _refreshTokenOnce() async {
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
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        await logout();
        throw AuthException('Сессия истекла. Войдите снова.');
      }
      throw AuthException('Token refresh failed');
    } catch (e) {
      if (e is AuthException) {
        rethrow;
      }
      if (_apiUnreachable(e) ||
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
    debugPrint('💾 Токены сохранены: access_token=$saved1, refresh_token=$saved2');
    
    // На веб-платформе нужно перезагрузить SharedPreferences для гарантии сохранения
    try {
      await prefs.reload();
    } catch (e) {
      debugPrint('⚠️ Не удалось перезагрузить SharedPreferences: $e');
    }
    
    // Проверяем, что токены действительно сохранены
    final verifyAccess = prefs.getString(_accessTokenKey);
    final verifyRefresh = prefs.getString(_refreshTokenKey);
    if (verifyAccess == null || verifyRefresh == null) {
      debugPrint('❌ ОШИБКА: Токены не сохранились!');
      debugPrint('   verifyAccess: ${verifyAccess != null ? "OK" : "NULL"}');
      debugPrint('   verifyRefresh: ${verifyRefresh != null ? "OK" : "NULL"}');
    } else {
      debugPrint('✅ Токены успешно сохранены и проверены');
      debugPrint('   access_token длина: ${verifyAccess.length}');
      debugPrint('   refresh_token длина: ${verifyRefresh.length}');
    }
  }
  
  static Future<void> _saveUser(User user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userJson = jsonEncode(user.toJson());
      final saved = await prefs.setString(_userKey, userJson);
      debugPrint('💾 Пользователь сохранен: ${user.email} (id: ${user.id}), saved=$saved');
      
      // На веб-платформе нужно перезагрузить SharedPreferences для гарантии сохранения
      try {
        await prefs.reload();
      } catch (e) {
        debugPrint('⚠️ Не удалось перезагрузить SharedPreferences: $e');
      }
      
      // Проверяем, что пользователь действительно сохранен
      final verifyUser = prefs.getString(_userKey);
      if (verifyUser == null) {
        debugPrint('❌ ОШИБКА: Пользователь не сохранился!');
      } else {
        debugPrint('✅ Пользователь успешно сохранен и проверен');
        debugPrint('   Длина JSON: ${verifyUser.length} символов');
        // Дополнительная проверка - пытаемся распарсить
        try {
          final parsedUser = User.fromJson(jsonDecode(verifyUser));
          debugPrint('✅ Пользователь успешно загружен из проверки: ${parsedUser.email} (id: ${parsedUser.id})');
        } catch (e) {
          debugPrint('❌ ОШИБКА: Не удалось распарсить сохраненного пользователя: $e');
          debugPrint('   JSON начало: ${verifyUser.substring(0, verifyUser.length > 100 ? 100 : verifyUser.length)}...');
        }
      }
    } catch (e) {
      debugPrint('❌ ОШИБКА при сохранении пользователя: $e');
      rethrow;
    }
  }
}

class AuthResponse {
  final String token;
  final String refreshToken;
  final User user;
  final String? message;

  AuthResponse({
    required this.token,
    required this.refreshToken,
    required this.user,
    this.message,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String,
      refreshToken: json['refresh_token'] as String,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      message: json['message'] as String?,
    );
  }
}

class MessageResponse {
  final String message;

  MessageResponse({required this.message});

  factory MessageResponse.fromJson(Map<String, dynamic> json) {
    return MessageResponse(message: json['message'] as String);
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
  /// С бэкенда (GET /users/me); для UI лимитов не показывать.
  final int? scanCredits;
  final String? subscriptionType;
  final bool emailVerified;
  final bool legalConsentRequired;
  final String? legalConsentVersion;
  final bool phoneLinked;

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
    this.scanCredits,
    this.subscriptionType,
    this.emailVerified = true,
    this.legalConsentRequired = false,
    this.legalConsentVersion,
    this.phoneLinked = false,
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
      scanCredits: (json['scan_credits'] as num?)?.toInt(),
      subscriptionType: json['subscription_type'] as String?,
      emailVerified: json['email_verified'] as bool? ?? true,
      legalConsentRequired: json['legal_consent_required'] as bool? ?? false,
      legalConsentVersion: json['legal_consent_version'] as String?,
      phoneLinked: json['phone_linked'] as bool? ?? false,
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
      'email_verified': emailVerified,
      if (scanCredits != null) 'scan_credits': scanCredits,
      if (subscriptionType != null) 'subscription_type': subscriptionType,
      'legal_consent_required': legalConsentRequired,
      if (legalConsentVersion != null)
        'legal_consent_version': legalConsentVersion,
    };
  }

  User copyWith({
    int? scanCredits,
    String? subscriptionType,
    bool? emailVerified,
    String? email,
    bool? legalConsentRequired,
    String? legalConsentVersion,
    bool? phoneLinked,
  }) {
    return User(
      id: id,
      email: email ?? this.email,
      name: name,
      username: username,
      avatarUrl: avatarUrl,
      bio: bio,
      isPrivate: isPrivate,
      isAdmin: isAdmin,
      isModerator: isModerator,
      createdAt: createdAt,
      scanCredits: scanCredits ?? this.scanCredits,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      emailVerified: emailVerified ?? this.emailVerified,
      legalConsentRequired:
          legalConsentRequired ?? this.legalConsentRequired,
      legalConsentVersion:
          legalConsentVersion ?? this.legalConsentVersion,
      phoneLinked: phoneLinked ?? this.phoneLinked,
    );
  }
}

class AuthException implements Exception {
  final String message;
  final String? code;

  AuthException(this.message, {this.code});

  bool get isEmailNotVerified => code == 'EMAIL_NOT_VERIFIED';

  @override
  String toString() => message;
}

AuthException _authExceptionFromResponse(
  http.Response response,
  String fallback,
) {
  try {
    final error = jsonDecode(response.body);
    if (error is Map<String, dynamic>) {
      final detail = error['detail'];
      if (detail is Map<String, dynamic>) {
        final code = detail['code'] as String?;
        final message = (detail['message'] as String?) ??
            (detail['detail'] as String?) ??
            fallback;
        return AuthException(message, code: code);
      }
      if (detail is String && detail.isNotEmpty) {
        return AuthException(detail);
      }
    }
  } catch (_) {}
  return AuthException(fallback);
}
