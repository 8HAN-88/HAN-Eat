import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/miniapps_service.dart';

/// Полноценный экран запуска мини-приложения с WebView + JS bridge (как Telegram WebApp).
class MiniAppWebViewScreen extends StatefulWidget {
  const MiniAppWebViewScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.htmlContent, // для self-contained demo мини-приложений
    this.url, // для внешних мини-приложений
    this.initData,
    this.initDataUnsafe,
    this.miniAppId,
    this.conversationId,
  });

  final String title;
  final String subtitle;
  final String? htmlContent;
  final String? url;
  final String? initData;
  final Map<String, dynamic>? initDataUnsafe;
  final int? miniAppId;
  final int? conversationId;

  @override
  State<MiniAppWebViewScreen> createState() => _MiniAppWebViewScreenState();
}

class _MiniAppWebViewScreenState extends State<MiniAppWebViewScreen> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _error;
  bool _mainButtonVisible = false;
  bool _mainButtonLoading = false;
  String _mainButtonText = 'Продолжить';
  bool _backButtonVisible = false;
  bool _sendingData = false;

  String get _effectiveInitData {
    final raw = widget.initData?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return '{"user":{"id":1,"first_name":"Demo","username":"demo"},"auth_date":1710000000,"hash":"demo_hash"}';
  }

  Map<String, dynamic> get _effectiveInitDataUnsafe {
    final fromWidget = widget.initDataUnsafe;
    if (fromWidget != null && fromWidget.isNotEmpty) return fromWidget;
    return const {
      'user': {'id': 1, 'first_name': 'Demo', 'username': 'demo'},
      'auth_date': 1710000000,
      'hash': 'demo_hash',
    };
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    final controller = _controller;
    if (controller == null) return;
    if (widget.url != null) {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(widget.url!)));
      return;
    }
    if (widget.htmlContent != null) {
      await controller.loadData(
        data: widget.htmlContent!,
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    }
  }

  Future<void> _openInBrowser() async {
    final raw = widget.url?.trim();
    if (raw == null || raw.isEmpty) return;
    await _openExternal(raw);
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Обновить'),
                onTap: () {
                  Navigator.pop(ctx);
                  _reload();
                },
              ),
              if ((widget.url ?? '').trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.open_in_browser_rounded),
                  title: const Text('Открыть в браузере'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openInBrowser();
                  },
                ),
              ListTile(
                leading: const Icon(Icons.close_rounded),
                title: const Text('Закрыть'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final subtitle = widget.subtitle.trim();

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: _backButtonVisible ? 'Назад' : 'Закрыть',
          icon: Icon(
            _backButtonVisible
                ? Icons.arrow_back_rounded
                : Icons.close_rounded,
          ),
          onPressed: () {
            if (_backButtonVisible) {
              unawaited(_emitBackButton());
              return;
            }
            Navigator.of(context).pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ещё',
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: _showMoreMenu,
          ),
          IconButton(
            tooltip: 'Закрыть',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (widget.htmlContent != null || widget.url != null)
            InAppWebView(
              initialData: widget.htmlContent != null
                  ? InAppWebViewInitialData(
                      data: widget.htmlContent!,
                      mimeType: 'text/html',
                      encoding: 'utf-8',
                    )
                  : null,
              initialUrlRequest: widget.url != null
                  ? URLRequest(url: WebUri(widget.url!))
                  : null,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                supportZoom: false,
                useShouldOverrideUrlLoading: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
                _injectWebAppBridge(controller);
                _registerHandlers(controller);
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                  _error = null;
                });
              },
              onLoadStop: (controller, url) async {
                setState(() => _isLoading = false);
                await controller.evaluateJavascript(
                  source:
                      'window.HanWe && window.HanWe.WebApp && window.HanWe.WebApp._ready();',
                );
              },
              onReceivedError: (controller, request, error) {
                setState(() {
                  _isLoading = false;
                  _error = error.description;
                });
              },
              shouldOverrideUrlLoading: (controller, action) async {
                final uri = action.request.url;
                if (uri == null) return NavigationActionPolicy.ALLOW;
                final scheme = uri.scheme.toLowerCase();
                if (scheme == 'http' || scheme == 'https') {
                  return NavigationActionPolicy.ALLOW;
                }
                await _openExternal(uri.toString());
                return NavigationActionPolicy.CANCEL;
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint(
                  '[MiniApp WebView] ${consoleMessage.messageLevel}: ${consoleMessage.message}',
                );
              },
            )
          else
            const Center(child: Text('Нет контента для отображения')),
          if (_isLoading)
            ColoredBox(
              color: colorScheme.surface.withValues(alpha: 0.72),
              child: const Center(child: CircularProgressIndicator()),
            ),
          if (_error != null)
            ColoredBox(
              color: colorScheme.surface,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Ошибка загрузки',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Закрыть'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: _reload,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _mainButtonVisible ? _buildBottomBar(context) : null,
    );
  }

  Future<void> _emitBackButton() async {
    await _controller?.evaluateJavascript(
      source: '''
        if (window.HanWe && window.HanWe.WebApp) {
          window.HanWe.WebApp._emit('backButtonClicked');
        }
      ''',
    );
  }

  void _triggerHaptic(String? type) {
    final kind = (type ?? 'impact').toLowerCase();
    switch (kind) {
      case 'success':
      case 'warning':
      case 'error':
      case 'rigid':
      case 'soft':
      case 'medium':
      case 'heavy':
        HapticFeedback.mediumImpact();
        break;
      case 'selection':
      case 'selectionchanged':
        HapticFeedback.selectionClick();
        break;
      case 'light':
      case 'impact':
      default:
        HapticFeedback.lightImpact();
        break;
    }
  }

  Future<void> _handleSendData(dynamic raw) async {
    if (_sendingData) return;
    final miniAppId = widget.miniAppId;
    if (miniAppId == null || miniAppId <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mini App не привязан к боту')),
      );
      return;
    }
    final data = raw is String
        ? raw
        : (raw == null ? '' : jsonEncode(raw));
    if (data.trim().isEmpty) return;
    setState(() => _sendingData = true);
    try {
      await MiniAppsService.sendWebAppData(
        miniAppId,
        data: data,
        conversationId: widget.conversationId,
        buttonText: widget.title,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingData = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отправить данные: $e')),
      );
    }
  }

  /// Регистрирует handlers для callHandler из JS (close, sendData)
  void _registerHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'close',
      callback: (args) {
        Navigator.of(context).pop();
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'sendData',
      callback: (args) {
        final data = args.isNotEmpty ? args.first : null;
        debugPrint('[MiniApp] sendData received: $data');
        unawaited(_handleSendData(data));
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'hapticFeedback',
      callback: (args) {
        final type = args.isNotEmpty ? args.first?.toString() : null;
        _triggerHaptic(type);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'openLink',
      callback: (args) async {
        final value = args.isNotEmpty ? (args.first?.toString() ?? '') : '';
        if (value.trim().isEmpty) return;
        await _openExternal(value);
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'mainButton',
      callback: (args) async {
        if (args.isEmpty || args.first is! Map) return;
        final payload = Map<String, dynamic>.from(args.first as Map);
        final visible = payload['visible'];
        final text = payload['text'];
        final loading = payload['loading'];
        if (!mounted) return;
        setState(() {
          if (visible is bool) _mainButtonVisible = visible;
          if (text is String && text.trim().isNotEmpty) {
            _mainButtonText = text.trim();
          }
          if (loading is bool) _mainButtonLoading = loading;
        });
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'backButton',
      callback: (args) async {
        if (args.isEmpty || args.first is! Map) return;
        final payload = Map<String, dynamic>.from(args.first as Map);
        final visible = payload['visible'];
        if (!mounted || visible is! bool) return;
        setState(() => _backButtonVisible = visible);
      },
    );
  }

  /// Инжектирует window.HanWe.WebApp bridge (аналог Telegram WebApp API)
  Future<void> _injectWebAppBridge(InAppWebViewController controller) async {
    final initDataSafe = jsonEncode(_effectiveInitData);
    final initDataUnsafeSafe = jsonEncode(_effectiveInitDataUnsafe);
    await controller.evaluateJavascript(source: '''
      (function() {
        if (window.HanWe && window.HanWe.WebApp) return;

        const callbacks = {};
        let eventListeners = {};

        window.HanWe = {
          WebApp: {
            initData: JSON.parse($initDataSafe),
            initDataUnsafe: JSON.parse($initDataUnsafeSafe),
            colorScheme: '${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}',
            themeParams: {
              bg_color: '${Theme.of(context).colorScheme.surface.value.toRadixString(16)}',
              text_color: '${Theme.of(context).colorScheme.onSurface.value.toRadixString(16)}',
              hint_color: '${Theme.of(context).colorScheme.outline.value.toRadixString(16)}',
              link_color: '${Theme.of(context).colorScheme.primary.value.toRadixString(16)}',
              button_color: '${Theme.of(context).colorScheme.primary.value.toRadixString(16)}',
              button_text_color: '${Theme.of(context).colorScheme.onPrimary.value.toRadixString(16)}',
            },
            isExpanded: true,
            viewportHeight: window.innerHeight,
            viewportStableHeight: window.innerHeight,
            platform: 'ios',
            version: '6.0',

            ready: function() {
              console.log('[HanWe.WebApp] ready() called');
            },

            expand: function() {
              console.log('[HanWe.WebApp] expand() called');
            },

            close: function() {
              window.HanWe.WebApp._close();
            },

            sendData: function(data) {
              window.HanWe.WebApp._sendData(data);
            },

            showAlert: function(message, callback) {
              alert(message);
              if (callback) callback();
            },

            showConfirm: function(message, callback) {
              const result = confirm(message);
              if (callback) callback(result);
            },

            openLink: function(url) {
              if (!url) return;
              window.flutter_inappwebview.callHandler('openLink', url);
            },

            HapticFeedback: {
              impactOccurred: function(style) {
                window.flutter_inappwebview.callHandler('hapticFeedback', String(style || 'impact'));
              },
              notificationOccurred: function(type) {
                window.flutter_inappwebview.callHandler('hapticFeedback', String(type || 'success'));
              },
              selectionChanged: function() {
                window.flutter_inappwebview.callHandler('hapticFeedback', 'selection');
              }
            },

            // Legacy flat helper used by some HanWe demos.
            hapticFeedback: function(type) {
              window.flutter_inappwebview.callHandler('hapticFeedback', String(type || 'impact'));
            },

            onEvent: function(eventType, callback) {
              if (!eventListeners[eventType]) eventListeners[eventType] = [];
              eventListeners[eventType].push(callback);
            },

            offEvent: function(eventType, callback) {
              if (eventListeners[eventType]) {
                eventListeners[eventType] = eventListeners[eventType].filter(cb => cb !== callback);
              }
            },

            // Внутренние методы
            _ready: function() {
              console.log('[HanWe.WebApp] _ready()');
              window.HanWe.WebApp._emit('ready');
            },

            _close: function() {
              window.flutter_inappwebview.callHandler('close');
            },

            _sendData: function(data) {
              window.flutter_inappwebview.callHandler('sendData', data);
            },

            _emit: function(eventType, payload) {
              if (eventListeners[eventType]) {
                eventListeners[eventType].forEach(cb => {
                  try { cb(payload); } catch (_) {}
                });
              }
            },
          }
        };

        window.HanWe.WebApp.MainButton = {
          setText: function(text) {
            window.flutter_inappwebview.callHandler('mainButton', { text: String(text || '') });
          },
          show: function() {
            window.flutter_inappwebview.callHandler('mainButton', { visible: true });
          },
          hide: function() {
            window.flutter_inappwebview.callHandler('mainButton', { visible: false });
          },
          showProgress: function() {
            window.flutter_inappwebview.callHandler('mainButton', { loading: true });
          },
          hideProgress: function() {
            window.flutter_inappwebview.callHandler('mainButton', { loading: false });
          },
          onClick: function(callback) {
            window.HanWe.WebApp.onEvent('mainButtonClicked', callback);
          }
        };

        window.HanWe.WebApp.BackButton = {
          show: function() {
            window.flutter_inappwebview.callHandler('backButton', { visible: true });
          },
          hide: function() {
            window.flutter_inappwebview.callHandler('backButton', { visible: false });
          },
          onClick: function(callback) {
            window.HanWe.WebApp.onEvent('backButtonClicked', callback);
          }
        };

        // Telegram WebApp alias for third-party Mini Apps.
        window.Telegram = window.Telegram || {};
        window.Telegram.WebApp = window.HanWe.WebApp;

        console.log('[HanWe] WebApp bridge injected');
      })();
    ''');
  }

  Widget _buildBottomBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _mainButtonLoading
                ? null
                : () async {
                    await _controller?.evaluateJavascript(
                      source: '''
                        if (window.HanWe && window.HanWe.WebApp) {
                          window.HanWe.WebApp._emit('mainButtonClicked');
                        }
                      ''',
                    );
                  },
            child: _mainButtonLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_mainButtonText),
          ),
        ),
      ),
    );
  }

  Future<void> _openExternal(String value) async {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
