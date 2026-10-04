import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final androidGranted = await android?.requestNotificationsPermission();
    final iosGranted = await ios?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    return androidGranted ?? iosGranted ?? true;
  }

  Future<void> showTestNotification() async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'deadline_alerts_v1',
        'Nhắc deadline',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );
    await _plugin.show(
      2147483000,
      'Thông báo đã hoạt động',
      'Bạn sẽ được nhắc trước deadline 10 phút và ngay khi quá hạn.',
      details,
    );
  }

  int _baseId(String taskId) =>
      taskId.codeUnits.fold<int>(17, (value, item) => value * 37 + item) &
      0x1fffffff;

  Future<void> cancelForTask(String taskId) async {
    await initialize();
    final id = _baseId(taskId);
    await _plugin.cancel(id);
    await _plugin.cancel(id + 1);
  }

  Future<void> scheduleForTask(PlannerTask task) async {
    await initialize();
    await cancelForTask(task.id);
    if (task.status == TaskStatus.completed) return;

    final now = DateTime.now();
    final reminderAt = task.deadline.subtract(const Duration(minutes: 10));
    final overdueAt = task.deadline;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'deadline_alerts_v1',
        'Nhắc deadline',
        channelDescription: 'Âm báo riêng cho deadline và công việc quá hạn',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        category: AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        threadIdentifier: 'deadline-alerts',
      ),
    );
    final id = _baseId(task.id);
    if (reminderAt.isAfter(now)) {
      await _plugin.zonedSchedule(
        id,
        'Còn 10 phút đến deadline',
        task.title,
        tz.TZDateTime.from(reminderAt.toUtc(), tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
    }
    if (overdueAt.isAfter(now)) {
      await _plugin.zonedSchedule(
        id + 1,
        'Công việc đã quá hạn',
        '${task.title} chưa được đánh dấu hoàn thành.',
        tz.TZDateTime.from(overdueAt.toUtc(), tz.UTC),
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
    }
  }

  Future<void> rescheduleAll(Iterable<PlannerTask> tasks) async {
    for (final task in tasks) {
      await scheduleForTask(task);
    }
  }
}
