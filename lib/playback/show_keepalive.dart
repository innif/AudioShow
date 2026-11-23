import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps screen on and the process alive (foreground service) during a show.
class ShowKeepAlive {
  static void init() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'show',
        channelName: 'Show läuft',
        channelDescription: 'Hält die Wiedergabe während der Show aktiv',
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
      ),
    );
  }

  static Future<void> enter(String showName) async {
    await WakelockPlus.enable();
    try {
      await FlutterForegroundTask.requestNotificationPermission();
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceTypes: [ForegroundServiceTypes.mediaPlayback],
          notificationTitle: 'Show läuft',
          notificationText: showName,
        );
      }
    } catch (_) {
      // Playback still works without the service; it is only a safety net.
    }
  }

  static Future<void> leave() async {
    await WakelockPlus.disable();
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
