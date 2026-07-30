import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:just_audio/just_audio.dart';
import 'package:vibration/vibration.dart';
import 'package:audio_session/audio_session.dart';

import '../data.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

final AudioPlayer _alarmPlayer = AudioPlayer();

Future<void> initActions() async {
  await _notificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@drawable/notification_icon'),
    ),
  );
  await _alarmPlayer.setAsset('other/alarm.mp3');
  final session = await AudioSession.instance;
  await session.configure(
    AudioSessionConfiguration(
      androidAudioAttributes: const AndroidAudioAttributes(
        contentType: AndroidAudioContentType.sonification,
        usage: AndroidAudioUsage.alarm,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gainTransient,
      androidWillPauseWhenDucked: false,
    ),
  );
}

Future<void> executeAction(ActionType action) async {
  switch (action) {
    case ActionType.none:
      break;
    case ActionType.notification:
      await _executeNotification();
      break;
    case ActionType.buzzing:
      await _executeBuzzing();
      break;
    case ActionType.loudAlarm:
      await _executeLoudAlarm();
      break;
  }
}

Future<void> _executeNotification() async {
  await _notificationsPlugin.show(
    999,
    'NordCoin Alert',
    'This is a test notification',
    const NotificationDetails(
      android: AndroidNotificationDetails(
        'action_test_id',
        'Action Test',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
  );
}

Future<void> _executeBuzzing() async {
  if (await Vibration.hasVibrator()) {
    await Vibration.vibrate(pattern: [0, 500, 200, 500]);
  }
}

Future<void> _executeLoudAlarm() async {
  await _alarmPlayer.seek(Duration.zero);
  await _alarmPlayer.play();
}


