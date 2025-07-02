import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_live_streaming_and_calls/service/zego_video_call_config.dart';
import 'package:zego_uikit/zego_uikit.dart';
import 'package:zego_uikit_prebuilt_call/zego_uikit_prebuilt_call.dart';
import 'package:zego_uikit_signaling_plugin/zego_uikit_signaling_plugin.dart';

class ZegoService {
  static final ZegoService _instance = ZegoService._internal();
  factory ZegoService() => _instance;
  ZegoService._internal();

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize({
    required User user,
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    if (_isInitialized) return;

    try {
      await ZegoUIKit().init(
        appID: ZegoConfig.appID,
        appSign: ZegoConfig.appSign,
        scenario: ZegoScenario.Default,
      );

      final signalingPlugin = ZegoUIKitSignalingPlugin();
      ZegoUIKit.instance.installPlugins([signalingPlugin]);

      await ZegoUIKitPrebuiltCallInvitationService().init(
        appID: ZegoConfig.appID,
        appSign: ZegoConfig.appSign,
        userID: user.uid,
        userName: user.displayName ?? 'Unknown User',
        plugins: [ZegoUIKitSignalingPlugin()],
        notificationConfig: ZegoCallInvitationNotificationConfig(
          androidNotificationConfig: ZegoCallAndroidNotificationConfig(
            showFullScreen: true,
            fullScreenBackgroundAssetURL: 'assets/image/call.png',
            callChannel: ZegoCallAndroidNotificationChannelConfig(
              channelID: "ZegoUIKit",
              channelName: "Call Notifications",
              sound: "call",
              icon: "call",
            ),
            missedCallChannel: ZegoCallAndroidNotificationChannelConfig(
              channelID: "MissedCall",
              channelName: "Missed Call",
              sound: "missed_call",
              icon: "missed_call",
              vibrate: false,
            ),
          ),
          iOSNotificationConfig: ZegoCallIOSNotificationConfig(
            systemCallingIconName: 'CallKitIcon',
          ),
        ),
        requireConfig: (ZegoCallInvitationData data) {
          final config =
              ZegoCallInvitationType.videoCall == data.type
                  ? ZegoUIKitPrebuiltCallConfig.oneOnOneVideoCall()
                  : ZegoUIKitPrebuiltCallConfig.oneOnOneVoiceCall();
          config.topMenuBar.isVisible = true;
          config.topMenuBar.buttons.insert(
            0,
            ZegoCallMenuBarButtonName.minimizingButton,
          );
          return config;
        },
      );

      ZegoUIKitPrebuiltCallInvitationService().setNavigatorKey(navigatorKey);
      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing ZEGO: $e');
      _isInitialized = false;
    }
  }

  void uninitialize() {
    if (!_isInitialized) return;
    ZegoUIKitPrebuiltCallInvitationService().uninit();
    _isInitialized = false;
  }
}
