import AVFoundation
import CallKit
import Flutter
import PushKit
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // PushKit VoIP — required for CallKit when the app is killed.
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry

    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FirebaseBootstrap.configureIfNeeded()
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - PKPushRegistryDelegate

  func pushRegistry(
    _ registry: PKPushRegistry,
    didUpdate credentials: PKPushCredentials,
    for type: PKPushType
  ) {
    let deviceToken = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didInvalidatePushTokenFor type: PKPushType
  ) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    guard type == .voIP else {
      completion()
      return
    }
    let raw = payload.dictionaryPayload
    let dataMap = (raw["data"] as? [String: Any]) ?? raw
    let callId = "\(dataMap["call_id"] ?? dataMap["callId"] ?? UUID().uuidString)"
    let uuid = Self.callUuid(from: callId)
    let name =
      (dataMap["caller_name"] as? String)
      ?? (dataMap["from_name"] as? String)
      ?? (dataMap["title"] as? String)
      ?? "Звонок"
    let media = (dataMap["media"] as? String) ?? "voice"
    let isVideo = media == "video"

    var info: [String: Any?] = [
      "id": uuid,
      "nameCaller": name,
      "handle": name,
      "type": isVideo ? 1 : 0,
      "duration": 60000,
      "extra": [
        "call_id": callId,
        "media": media,
        "conversation_id": "\(dataMap["conversation_id"] ?? "")",
        "caller_name": name,
      ],
    ]
    if let avatar = dataMap["caller_avatar"] as? String ?? dataMap["from_avatar_url"] as? String {
      info["avatar"] = avatar
    }

    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(
      flutter_callkit_incoming.Data(args: info),
      fromPushKit: true
    )
    // Apple requires completion soon after reporting the call to CallKit.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      completion()
    }
  }

  private static func callUuid(from callId: String) -> String {
    if let n = Int(callId) {
      let hex = String(format: "%012x", n)
      return "00000000-0000-4000-8000-\(hex)"
    }
    return UUID().uuidString
  }
}
