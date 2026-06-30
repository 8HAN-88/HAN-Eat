import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Полноценный экран запуска мини-приложения с WebView + JS bridge (как Telegram WebApp).
class MiniAppWebViewScreen extends StatefulWidget {
  const MiniAppWebViewScreen({
    super.key,
    required this.title,
    required this.subtitle,
    this.htmlContent, // для self-contained demo мини-приложений
    this.url, // для внешних мини-приложений
  });

  final String title;
  final String subtitle;
  final String? htmlContent;
  final String? url;

  @override
  State<MiniAppWebViewScreen> createState() => _MiniAppWebViewScreenState();
}

class _MiniAppWebViewScreenState extends State<MiniAppWebViewScreen> {
  InAppWebViewController? _controller;
  bool _isLoading = true;
  String? _error;

  // TODO: В будущем генерировать настоящий initData с HMAC-подписью на бэкенде
  final String _initData = '{"user":{"id":1,"first_name":"Demo","username":"demo"},"auth_date":1710000000,"hash":"demo_hash"}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (widget.htmlContent != null || widget.url != null)
            InAppWebView(
              initialData: widget.htmlContent != null
                  ? InAppWebViewInitialData(data: widget.htmlContent!, mimeType: 'text/html', encoding: 'utf-8')
                  : null,
              initialUrlRequest: widget.url != null ? URLRequest(url: WebUri(widget.url!)) : null,
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
                setState(() => _isLoading = true);
              },
              onLoadStop: (controller, url) async {
                setState(() => _isLoading = false);
                // Сообщаем мини-приложению, что WebApp готов
                await controller.evaluateJavascript(source: 'window.HanWe && window.HanWe.WebApp && window.HanWe.WebApp._ready();');
              },
              onReceivedError: (controller, request, error) {
                setState(() {
                  _isLoading = false;
                  _error = error.description;
                });
              },
              onConsoleMessage: (controller, consoleMessage) {
                debugPrint('[MiniApp WebView] ${consoleMessage.messageLevel}: ${consoleMessage.message}');
              },
            )
          else
            const Center(child: Text('Нет контента для отображения')),

          if (_isLoading)
            Container(
              color: colorScheme.surface.withOpacity(0.8),
              child: const Center(child: CircularProgressIndicator()),
            ),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text('Ошибка загрузки', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(context),
    );
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
        // TODO: Здесь можно отправить данные на бэкенд или обработать в приложении
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MiniApp sent data: $data')),
        );
      },
    );
  }

  /// Инжектирует window.HanWe.WebApp bridge (аналог Telegram WebApp API)
  Future<void> _injectWebAppBridge(InAppWebViewController controller) async {
    await controller.evaluateJavascript(source: '''
      (function() {
        if (window.HanWe && window.HanWe.WebApp) return;

        const callbacks = {};
        let eventListeners = {};

        window.HanWe = {
          WebApp: {
            initData: '$_initData',
            initDataUnsafe: JSON.parse('$_initData'),
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

            hapticFeedback: function(type) {
              console.log('[HanWe.WebApp] hapticFeedback:', type);
              // TODO: Реализовать через platform channel
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
              if (eventListeners['ready']) {
                eventListeners['ready'].forEach(cb => cb());
              }
            },

            _close: function() {
              window.flutter_inappwebview.callHandler('close');
            },

            _sendData: function(data) {
              window.flutter_inappwebview.callHandler('sendData', data);
            },
          }
        };

        console.log('[HanWe] WebApp bridge injected');
      })();
    ''');
  }

  Widget _buildBottomBar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          Text(
            'HanWe Mini App',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colorScheme.outline),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}
