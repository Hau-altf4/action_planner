// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:html' as html;

import '../models/task.dart';

class NotificationService {
  NotificationService._();

  static final instance = NotificationService._();
  final Map<String, List<_WebAlarm>> _alarms = {};
  final Set<String> _shown = {};
  final html.AudioElement _alertSound = html.AudioElement(
    'data:audio/wav;base64,UklGRuQDAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YcADAACAudjPoWQ0J0J6tdfRpmo3Jj51sNbUq287Jjtvq9TWsHU+JjdqptHXtXpCJzRkoc/YuYBHKDFfnMzZvoZLKS9alsnawotQKixVkcXaxZFVLCpQi8LayZZaLylLhr7ZzJxfMShHgLnYz6FkNCdCerXX0aZqNyY+dbDW1KtvOyY7b6vU1rB1PiY3aqbR17V6Qic0ZKHP2LmARygxX5zM2b6GSykvWpbJ2sKLUCosVZHF2sWRVSwqUIvC2smWWi8pS4a+2cycXzEoR4C52M+hZDQnQnq119GmajcmPnWw1tSrbzsmO2+r1NawdT4mN2qm0de1ekInNGShz9i5gEcoMV+czNm+hkspL1qWydrCi1AqLFWRxdrFkVUsKlCLwtrJllovKUuGvtnMnF8xKEeAudjPoWQ0J0J6tdfRpmo3Jj51sNbUq287Jjtvq9TWsHU+JjdqptHXtXpCJzRkoc/YuYBHKDFfnMzZvoZLKS9alsnawotQKixVkcXaxZFVLCpQi8LayZZaLylLhr7ZzJxfMShHgLnYz6FkNCdCerXX0aZqNyY+dbDW1KtvOyY7b6vU1rB1PiY3aqbR17V6Qic0ZKHP2LmARygxX5zM2b6GSykvWpbJ2sKLUCosVZHF2sWRVSwqUIvC2smWWi8pS4a+2cycXzEoR4C52M+hZDQnQnq119GmajcmPnWw1tSrbzsmO2+r1NawdT4mN2qm0de1ekInNGShz9i5gEcoMV+czNm+hkspL1qWydrCi1AqLFWRxdrFkVUsKlCLwtrJllovKUuGvtnMnF8xKEeAudjPoWQ0J0J6tdfRpmo3Jj51sNbUq287Jjtvq9TWsHU+JjdqptHXtXpCJzRkoc/YuYBHKDFfnMzZvoZLKS9alsnawotQKixVkcXaxZFVLCpQi8LayZZaLylLhr7ZzJxfMShHgLnYz6FkNCdCerXX0aZqNyY+dbDW1KtvOyY7b6vU1rB1PiY3aqbR17V6Qic0ZKHP2LmARygxX5zM2b6GSykvWpbJ2sKLUCosVZHF2sWRVSwqUIvC2smWWi8pS4a+2cycXzEoR4C52M+hZDQnQnq119GmajcmPnWw1tSrbzsmO2+r1NawdT4mN2qm0de1ekInNGShz9i5gEcoMV+czNm+hkspL1qWydrCi1AqLFWRxdrFkVUsKlCLwtrJllovKUuGvtnMnF8xKEeAudjPoWQ0J0J6tdfRpmo3Jj51sNbUq287Jjtvq9TWsHU+JjdqptHXtXpCJzRkoc/YuYBHKDFfnMzZvoZLKS9alsnawotQKixVkcXaxZFVLCpQi8LayZZaLylLhr7ZzJxfMShHgLnYz6FkNCdCerXX0aZqNyY+dbDW1KtvOyY7b6vU1rB1PiY3aqbR17V6Qic0ZKHP2LmARygxX5zM2b6GSykvWpbJ2sKLUCosVZHF2sWRVSwqUIvC2smWWi8pS4a+2cycXzEoR4C52M+hZDQnQnq119GmajcmPnWw1tSrbzsmO2+r1NawdT4mN2qm0de1ekInNGShz9i5gEcoMV+czNm+hkspL1qWydrCi1AqLFWRxdrFkVUsKlCLwtrJllovKUuGvtnMnF8xKEeAudjPoWQ0J0J6tdfRpmo3Jj51sNbUq287Jjtvq9TWsHU+JjdqptHXtXpCJzRkoc/YuYBHKDFfnMzZvoY=',
  );

  Future<void> initialize() async {}

  Future<bool> requestPermission() async {
    try {
      _alertSound
        ..volume = 0
        ..currentTime = 0;
      await _alertSound.play();
      _alertSound
        ..pause()
        ..volume = 1;
    } catch (_) {
      // Safari có thể không cho khởi tạo âm thanh; cảnh báo chữ vẫn hoạt động.
    }
    html.window.localStorage['deadline_reminders_enabled'] = 'true';
    if (!html.Notification.supported) return true;
    try {
      if (html.Notification.permission == 'granted') return true;
      await html.Notification.requestPermission();
    } catch (_) {
      // HTTP trên iOS/desktop có thể chặn Notification API. Nhắc trong trang
      // vẫn hoạt động nên không coi đây là lỗi bật nhắc deadline.
    }
    // Dù thông báo hệ thống bị chặn trên HTTP/iOS, nhắc trong trang vẫn chạy.
    return true;
  }

  Future<void> showTestNotification() async {
    _shown.remove('notification-test');
    _show(
      'notification-test',
      'Thông báo đã hoạt động',
      'Bạn sẽ được nhắc trước deadline 10 phút và ngay khi quá hạn.',
    );
  }

  Future<void> cancelForTask(String taskId) async {
    for (final alarm in _alarms.remove(taskId) ?? const <_WebAlarm>[]) {
      alarm.cancel();
    }
  }

  void _show(String key, String title, String body) {
    if (!_shown.add(key)) return;
    _playSound();
    if (html.Notification.supported &&
        html.Notification.permission == 'granted') {
      html.Notification(title, body: body, tag: key);
    } else if (html.document.visibilityState == 'visible') {
      Timer(
        const Duration(milliseconds: 450),
        () => html.window.alert('$title\n\n$body'),
      );
    }
  }

  void _playSound() {
    try {
      _alertSound
        ..volume = 1
        ..currentTime = 0;
      final firstPlay = _alertSound.play();
      firstPlay.catchError((_) {});
      Timer(const Duration(milliseconds: 260), () {
        try {
          _alertSound.currentTime = 0;
          final secondPlay = _alertSound.play();
          secondPlay.catchError((_) {});
        } catch (_) {}
      });
    } catch (_) {}
  }

  Future<void> scheduleForTask(PlannerTask task) async {
    await cancelForTask(task.id);
    if (task.status == TaskStatus.completed) return;
    final now = DateTime.now();
    final reminderAt = task.deadline.subtract(const Duration(minutes: 10));
    final overdueAt = task.deadline;
    final alarms = <_WebAlarm>[];
    if (reminderAt.isAfter(now)) {
      alarms.add(
        _WebAlarm(
          reminderAt,
          () => _show(
            '${task.id}-reminder',
            'Còn 10 phút đến deadline',
            task.title,
          ),
        )..start(),
      );
    }
    if (overdueAt.isAfter(now)) {
      alarms.add(
        _WebAlarm(
          overdueAt,
          () => _show(
            '${task.id}-overdue',
            'Công việc đã quá hạn',
            '${task.title} chưa được đánh dấu hoàn thành.',
          ),
        )..start(),
      );
    } else {
      scheduleMicrotask(
        () => _show(
          '${task.id}-overdue',
          'Công việc đã quá hạn',
          '${task.title} chưa được đánh dấu hoàn thành.',
        ),
      );
    }
    _alarms[task.id] = alarms;
  }

  Future<void> rescheduleAll(Iterable<PlannerTask> tasks) async {
    for (final task in tasks) {
      await scheduleForTask(task);
    }
  }
}

class _WebAlarm {
  _WebAlarm(this.target, this.callback);

  final DateTime target;
  final void Function() callback;
  Timer? _timer;
  bool _cancelled = false;

  void start() {
    if (_cancelled) return;
    final remaining = target.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      callback();
      return;
    }
    const checkpoint = Duration(hours: 12);
    _timer = Timer(remaining > checkpoint ? checkpoint : remaining, start);
  }

  void cancel() {
    _cancelled = true;
    _timer?.cancel();
  }
}
