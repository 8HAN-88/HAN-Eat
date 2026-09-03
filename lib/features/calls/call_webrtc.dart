import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

/// Web-safe WebRTC helpers. `flutter_webrtc` still routes speaker/init
/// through `FlutterWebRTC.Method`, which is not registered on PWA/Safari.
class CallWebrtc {
  CallWebrtc._();

  static bool isPluginMissing(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('missingpluginexception') &&
        (lower.contains('flutterwebrtc') ||
            lower.contains('webrtc') ||
            lower.contains('permission'));
  }

  static bool isMediaPermissionError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('notallowederror') ||
        lower.contains('permission denied') ||
        lower.contains('permissiondismissed') ||
        lower.contains('securityerror') ||
        lower.contains('notallowed');
  }

  static bool isMediaMissingError(Object error) {
    final lower = error.toString().toLowerCase();
    return lower.contains('notfounderror') ||
        lower.contains('devicenotfound') ||
        lower.contains('requested device not found');
  }

  static String humanError(Object error, {required bool video}) {
    if (isPluginMissing(error)) {
      return 'Не удалось запустить звонок в браузере. Обновите страницу и нажмите «Повторить».';
    }
    if (isMediaPermissionError(error)) {
      return video
          ? 'Разрешите доступ к микрофону и камере — Safari спросит ещё раз после нажатия.'
          : 'Разрешите доступ к микрофону — Safari спросит ещё раз после нажатия.';
    }
    if (isMediaMissingError(error)) {
      return video
          ? 'Камера или микрофон не найдены. Проверьте, что они не заняты другим приложением.'
          : 'Микрофон не найден. Проверьте, что он не занят другим приложением.';
    }
    final lower = error.toString().toLowerCase();
    if (lower.contains('overconstrained') || lower.contains('constraint')) {
      return video
          ? 'Камера не поддерживает этот режим. Попробуйте голосовой звонок или другую камеру.'
          : 'Не удалось захватить микрофон. Попробуйте ещё раз.';
    }
    if (lower.contains('notreadable') || lower.contains('trackstart')) {
      return 'Микрофон или камера заняты. Закройте другие вкладки и повторите.';
    }
    return error.toString().replaceAll('Exception: ', '').trim();
  }

  static Map<String, dynamic> audioConstraints() => {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      };

  static Object videoConstraints({bool simple = false}) {
    if (simple) {
      return {
        'facingMode': 'user',
      };
    }
    return {
      'facingMode': 'user',
      'width': {'ideal': kIsWeb ? 640 : 1280},
      'height': {'ideal': kIsWeb ? 480 : 720},
      'frameRate': {'ideal': 30},
    };
  }

  static Map<String, dynamic> peerConfiguration(
    List<Map<String, dynamic>> iceServers,
  ) {
    final servers = iceServers.isEmpty
        ? const [
            {'urls': 'stun:stun.l.google.com:19302'},
            {'urls': 'stun:stun1.l.google.com:19302'},
            {'urls': 'stun:stun.cloudflare.com:3478'},
          ]
        : iceServers;
    return {
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 2,
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    };
  }

  static int? iceLineIndex(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  static Future<void> initializeRenderer(RTCVideoRenderer renderer) async {
    try {
      await renderer.initialize();
    } catch (e) {
      if (kIsWeb && isPluginMissing(e)) return;
      rethrow;
    }
  }

  static Future<void> setSpeakerphone(bool on) async {
    if (kIsWeb) return;
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (e) {
      if (isPluginMissing(e)) return;
      rethrow;
    }
  }

  static Future<void> switchCamera(MediaStreamTrack track) async {
    try {
      await Helper.switchCamera(track);
    } catch (e) {
      if (kIsWeb && isPluginMissing(e)) return;
      rethrow;
    }
  }

  /// Native permission_handler. On web Safari the Permissions API is incomplete
  /// and a failed plugin register would abort the call — skip it.
  static Future<bool> ensureNativePermissions({required bool video}) async {
    if (kIsWeb) return true;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (video) {
      final camera = await Permission.camera.request();
      if (!camera.isGranted) return false;
    }
    try {
      await Permission.bluetoothConnect.request();
    } catch (_) {}
    return true;
  }

  static Future<MediaStream> getUserMediaSafe({required bool video}) async {
    Future<MediaStream> grab(Object videoConstraint) {
      return navigator.mediaDevices.getUserMedia({
        'audio': audioConstraints(),
        'video': videoConstraint,
      });
    }

    if (!video) {
      try {
        return await grab(false);
      } catch (_) {
        return navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': false,
        });
      }
    }

    try {
      return await grab(videoConstraints());
    } catch (_) {}
    try {
      return await grab(videoConstraints(simple: true));
    } catch (_) {}
    try {
      return await grab(true);
    } catch (_) {
      return grab(false);
    }
  }
}
