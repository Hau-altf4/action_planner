import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/task_repository.dart';
import '../models/schedule_item.dart';
import '../models/task.dart';
import '../services/notification_service.dart';

class ChatMessage {
  const ChatMessage(this.text, {required this.fromUser});

  final String text;
  final bool fromUser;
}

class AppState extends ChangeNotifier {
  AppState(this.repository);

  final TaskRepository repository;
  final List<PlannerTask> tasks = [];
  final List<ChatMessage> messages = const [
    ChatMessage(
      'Xin chào! Mình có thể giúp bạn chia nhỏ công việc, đánh giá ưu tiên '
      'hoặc xem lịch hôm nay. Bạn có thể chọn một câu hỏi gợi ý bên dưới.',
      fromUser: false,
    ),
  ].toList();

  bool isSignedIn = false;
  // Hiển thị màn hình đăng nhập ngay; phiên đã lưu được khôi phục nền để tránh
  // một màn hình chờ không cần thiết khi mở ứng dụng.
  bool isBootstrapping = false;
  bool isLoading = false;
  bool isAiBusy = false;
  String userName = '';
  String userEmail = '';
  String userRole = 'user';
  VoiceSettings voiceSettings = const VoiceSettings();
  String? error;

  bool get isAdmin => userRole == 'admin';

  Future<void> bootstrap() async {
    try {
      final user = await repository.restoreSession();
      if (user != null) {
        userName = user.fullName;
        userEmail = user.email;
        userRole = user.role;
        isSignedIn = true;
        final cached = await repository.getCachedTasks();
        if (cached.isNotEmpty) {
          tasks
            ..clear()
            ..addAll(cached);
          notifyListeners();
        }
        await load();
        await loadVoiceSettings();
      }
    } finally {
      isBootstrapping = false;
      notifyListeners();
    }
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      tasks
        ..clear()
        ..addAll(await repository.getTasks());
      await _ensureFixedSchedule();
      await NotificationService.instance.rescheduleAll(tasks);
      unawaited(prefetchScheduleSpeech());
    } catch (exception) {
      error = '$exception';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signIn({
    required String name,
    required String email,
    required String password,
    required bool register,
  }) async {
    final user = await repository.authenticate(
      name: name,
      email: email,
      password: password,
      register: register,
    );
    userName = user.fullName;
    userEmail = user.email;
    userRole = user.role;
    messages
      ..clear()
      ..add(
        const ChatMessage(
          'Xin chào! Mình có thể giúp bạn chia nhỏ công việc, đánh giá ưu tiên '
          'hoặc xem lịch hôm nay. Bạn có thể chọn một câu hỏi gợi ý bên dưới.',
          fromUser: false,
        ),
      );
    isSignedIn = true;
    await load();
    await loadVoiceSettings();
  }

  void signOut() {
    repository.signOut();
    for (final task in tasks) {
      NotificationService.instance.cancelForTask(task.id);
    }
    tasks.clear();
    messages
      ..clear()
      ..add(
        const ChatMessage(
          'Xin chào! Mình có thể giúp bạn chia nhỏ công việc, đánh giá ưu tiên '
          'hoặc xem lịch hôm nay. Bạn có thể chọn một câu hỏi gợi ý bên dưới.',
          fromUser: false,
        ),
      );
    userName = '';
    userEmail = '';
    userRole = 'user';
    voiceSettings = const VoiceSettings();
    error = null;
    isSignedIn = false;
    notifyListeners();
  }

  Future<void> saveTask(PlannerTask task) async {
    task.scheduledStart ??= _nextScheduleStart();
    final saved = await repository.saveTask(task);
    final index = tasks.indexWhere((item) => item.id == saved.id);
    if (index < 0) {
      tasks.add(saved);
    } else {
      tasks[index] = saved;
    }
    await NotificationService.instance.scheduleForTask(saved);
    notifyListeners();
  }

  Future<void> setStatus(PlannerTask task, TaskStatus status) async {
    await repository.updateStatus(task.id, status);
    task.status = status;
    await NotificationService.instance.scheduleForTask(task);
    notifyListeners();
  }

  Future<AiTaskAnalysis> analyzeTask(String title, String description) =>
      repository.analyzeTask(title, description);

  void toggleStep(PlannerTask task, TaskStep step, bool completed) {
    step.isCompleted = completed;
    if (task.progress == 1) task.status = TaskStatus.completed;
    notifyListeners();
    repository.saveTask(task);
  }

  Future<void> askAi(String text) async {
    if (text.trim().isEmpty || isAiBusy) return;
    final history = messages
        .skip(messages.length > 10 ? messages.length - 10 : 0)
        .map(
          (message) => {
            'role': message.fromUser ? 'user' : 'assistant',
            'content': message.text,
          },
        )
        .toList();
    messages.add(ChatMessage(text.trim(), fromUser: true));
    isAiBusy = true;
    notifyListeners();
    try {
      messages.add(
        ChatMessage(
          await repository.askAi(text, history: history),
          fromUser: false,
        ),
      );
    } catch (exception) {
      messages.add(
        ChatMessage('Không thể kết nối AI: $exception', fromUser: false),
      );
    } finally {
      isAiBusy = false;
      notifyListeners();
    }
  }

  Future<ReplanProposal> proposeReplan({String feedback = ''}) async {
    isLoading = true;
    notifyListeners();
    try {
      return await repository.proposeReplan(feedback: feedback);
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> acceptReplan(ReplanProposal proposal) async {
    isLoading = true;
    notifyListeners();
    try {
      final replanned = await repository.acceptReplan(proposal);
      tasks
        ..clear()
        ..addAll(replanned);
      await _ensureFixedSchedule();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<AiSettings> getAiSettings({bool admin = false}) =>
      repository.getAiSettings(admin: admin);

  Future<AiSettings> saveAiSettings(
    AiSettings settings, {
    bool admin = false,
  }) => repository.saveAiSettings(settings, admin: admin);

  Future<void> testAiSettings() => repository.testAiSettings();

  Future<void> loadVoiceSettings() async {
    try {
      voiceSettings = await repository.getVoiceSettings();
      notifyListeners();
      unawaited(prefetchScheduleSpeech());
    } catch (_) {
      // Giọng hệ thống vẫn hoạt động với cấu hình mặc định khi offline.
    }
  }

  Future<VoiceSettings> saveVoiceSettings(VoiceSettings settings) async {
    voiceSettings = await repository.saveVoiceSettings(settings);
    notifyListeners();
    unawaited(prefetchScheduleSpeech());
    return voiceSettings;
  }

  Future<Uint8List> synthesizeSpeech(String text) =>
      repository.synthesizeSpeech(text);

  String scheduleItemSpeech(ScheduleItem item) =>
      'Từ ${_spokenTime(item.start)} đến ${_spokenTime(item.end)}, '
      'bạn làm công việc ${item.title}.';

  String dayScheduleSpeech([List<ScheduleItem>? items]) {
    final selected = items ?? schedule;
    final details = selected.map(scheduleItemSpeech).join(' ');
    return 'Từ những công việc bạn đã đưa ra, mình sắp xếp kế hoạch '
        'trong ngày như thế này. $details';
  }

  Future<void> prefetchScheduleSpeech() async {
    final items = schedule;
    if (items.isEmpty || !voiceSettings.configured) return;
    try {
      await repository.prefetchSpeech([
        dayScheduleSpeech(items),
        ...items.map(scheduleItemSpeech),
      ]);
    } catch (_) {
      // Làm nóng cache là tối ưu tùy chọn, không ảnh hưởng lịch chính.
    }
  }

  String _spokenTime(DateTime value) => value.minute == 0
      ? '${value.hour} giờ'
      : '${value.hour} giờ ${value.minute} phút';

  Future<void> submitFeedback({
    required String type,
    required String message,
    int? rating,
  }) => repository.submitFeedback(type: type, message: message, rating: rating);

  List<ScheduleItem> get schedule {
    final planned = tasks
        .where((task) => task.status != TaskStatus.completed)
        .toList();
    var cursor = _initialScheduleCursor();
    return planned.map((task) {
      final start = task.scheduledStart ?? cursor;
      final end = start.add(Duration(minutes: task.estimatedMinutes));
      cursor = end.add(const Duration(minutes: 10));
      return ScheduleItem(
        taskId: task.id,
        title: task.title,
        start: start,
        end: end,
      );
    }).toList();
  }

  DateTime _initialScheduleCursor() {
    final now = DateTime.now();
    if (now.hour < 8) return DateTime(now.year, now.month, now.day, 8);
    return DateTime(now.year, now.month, now.day, now.hour, now.minute);
  }

  DateTime _nextScheduleStart() {
    var cursor = _initialScheduleCursor();
    for (final task in tasks.where(
      (task) =>
          task.status != TaskStatus.completed && task.scheduledStart != null,
    )) {
      final next = task.scheduledStart!
          .add(Duration(minutes: task.estimatedMinutes))
          .add(const Duration(minutes: 10));
      if (next.isAfter(cursor)) cursor = next;
    }
    return cursor;
  }

  Future<void> _ensureFixedSchedule() async {
    var cursor = _initialScheduleCursor();
    for (var index = 0; index < tasks.length; index++) {
      final task = tasks[index];
      if (task.status == TaskStatus.completed) continue;
      if (task.scheduledStart == null) {
        task.scheduledStart = cursor;
        final saved = await repository.saveTask(task);
        tasks[index] = saved;
      }
      final next = task.scheduledStart!
          .add(Duration(minutes: task.estimatedMinutes))
          .add(const Duration(minutes: 10));
      if (next.isAfter(cursor)) cursor = next;
    }
  }
}
