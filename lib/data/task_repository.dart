import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/task.dart';

abstract class TaskRepository {
  static const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const _configuredApiFallbackUrl = String.fromEnvironment(
    'API_FALLBACK_URL',
  );
  static const usesMockData = bool.fromEnvironment('USE_MOCK_DATA');

  static String get apiBaseUrl {
    if (_configuredApiBaseUrl.isNotEmpty) return _configuredApiBaseUrl;
    if (kIsWeb) {
      final page = Uri.base;
      final host = page.host.isEmpty ? '127.0.0.1' : page.host;
      return '${page.scheme == 'https' ? 'https' : 'http'}://$host:3000';
    }
    return 'http://127.0.0.1:3000';
  }

  static TaskRepository create() => usesMockData
      ? MockTaskRepository()
      : ApiTaskRepository(
          apiBaseUrl,
          fallbackBaseUrl: _configuredApiFallbackUrl,
        );

  Future<List<PlannerTask>> getTasks();
  Future<List<PlannerTask>> getCachedTasks();
  Future<String> checkConnection();
  Future<AuthenticatedUser?> restoreSession();
  Future<AuthenticatedUser> authenticate({
    required String name,
    required String email,
    required String password,
    required bool register,
  });
  Future<PlannerTask> saveTask(PlannerTask task);
  Future<void> updateStatus(String id, TaskStatus status);
  Future<AiTaskAnalysis> analyzeTask(String title, String description);
  Future<String> askAi(
    String message, {
    List<Map<String, String>> history = const [],
  });
  Future<ReplanProposal> proposeReplan({String feedback = ''});
  Future<List<PlannerTask>> acceptReplan(ReplanProposal proposal);
  Future<AiSettings> getAiSettings({bool admin = false});
  Future<AiSettings> saveAiSettings(AiSettings settings, {bool admin = false});
  Future<void> testAiSettings();
  Future<void> submitFeedback({
    required String type,
    required String message,
    int? rating,
  });
  Future<List<Map<String, dynamic>>> getMyFeedback();
  Future<Map<String, dynamic>> getAdminDashboard();
  Future<List<Map<String, dynamic>>> getAdminUsers();
  Future<List<Map<String, dynamic>>> getAdminFeedback();
  Future<void> updateFeedbackStatus(
    String id,
    String status, {
    String adminReply = '',
  });
  void signOut();
}

class AuthenticatedUser {
  const AuthenticatedUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.role = 'user',
  });

  final String id;
  final String fullName;
  final String email;
  final String role;

  bool get isAdmin => role == 'admin';
}

class AiSettings {
  const AiSettings({
    this.provider = 'ollama',
    this.model = 'qwen3:1.7b',
    this.baseUrl = '',
    this.apiKey = '',
    this.customAiEnabled = false,
    this.hasApiKey = false,
    this.source = 'environment',
  });

  final String provider;
  final String model;
  final String baseUrl;
  final String apiKey;
  final bool customAiEnabled;
  final bool hasApiKey;
  final String source;

  factory AiSettings.fromJson(Map<String, dynamic> json) => AiSettings(
    provider: '${json['provider'] ?? 'ollama'}',
    model: '${json['model'] ?? ''}',
    baseUrl: '${json['baseUrl'] ?? ''}',
    customAiEnabled: json['customAiEnabled'] == true,
    hasApiKey: json['hasApiKey'] == true,
    source: '${json['source'] ?? 'environment'}',
  );

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'model': model,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'customAiEnabled': customAiEnabled,
  };
}

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class MockTaskRepository implements TaskRepository {
  final List<PlannerTask> _tasks = [];

  @override
  Future<AuthenticatedUser> authenticate({
    required String name,
    required String email,
    required String password,
    required bool register,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return AuthenticatedUser(
      id: 'mock-user',
      fullName: register && name.trim().isNotEmpty ? name.trim() : 'Người dùng',
      email: email.trim().toLowerCase(),
    );
  }

  @override
  Future<List<PlannerTask>> getCachedTasks() async => List.of(_tasks);

  @override
  Future<String> checkConnection() async => 'Dữ liệu mẫu';

  @override
  Future<AuthenticatedUser?> restoreSession() async => null;

  @override
  Future<List<PlannerTask>> getTasks() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    return List.of(_tasks);
  }

  @override
  Future<PlannerTask> saveTask(PlannerTask task) async {
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) {
      _tasks.add(task);
    } else {
      _tasks[index] = task;
    }
    return task;
  }

  @override
  Future<void> updateStatus(String id, TaskStatus status) async {
    _tasks.firstWhere((item) => item.id == id).status = status;
  }

  @override
  Future<AiTaskAnalysis> analyzeTask(String title, String description) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return AiTaskAnalysis(
      priority: title.toLowerCase().contains('gấp')
          ? TaskPriority.urgent
          : TaskPriority.high,
      estimatedMinutes: 60,
      steps: const [
        'Xác định kết quả cần đạt',
        'Thực hiện phần chính',
        'Kiểm tra và hoàn thiện',
      ],
      suggestion: 'Bắt đầu bằng một phiên tập trung 50 phút và tắt thông báo.',
    );
  }

  @override
  Future<String> askAi(
    String message, {
    List<Map<String, String>> history = const [],
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return 'Gợi ý: hãy chia “$message” thành các bước nhỏ, ưu tiên phần có '
        'hạn gần nhất và dành một khoảng nghỉ ngắn sau mỗi 50 phút.';
  }

  @override
  Future<ReplanProposal> proposeReplan({String feedback = ''}) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final ordered = [..._tasks]
      ..sort((a, b) {
        final priority = b.priority.index.compareTo(a.priority.index);
        return priority != 0 ? priority : a.deadline.compareTo(b.deadline);
      });
    return ReplanProposal(
      summary: feedback.isEmpty
          ? 'Đề xuất ưu tiên công việc quan trọng và có deadline gần.'
          : 'Đã điều chỉnh phương án theo phản hồi: $feedback',
      tasks: ordered,
    );
  }

  @override
  Future<List<PlannerTask>> acceptReplan(ReplanProposal proposal) async {
    _tasks
      ..clear()
      ..addAll(proposal.tasks);
    var cursor = DateTime.now();
    cursor = DateTime(
      cursor.year,
      cursor.month,
      cursor.day,
      cursor.hour,
      cursor.minute,
    );
    for (final task in _tasks) {
      task.scheduledStart = cursor;
      cursor = cursor
          .add(Duration(minutes: task.estimatedMinutes))
          .add(const Duration(minutes: 10));
    }
    return List.of(_tasks);
  }

  @override
  Future<AiSettings> getAiSettings({bool admin = false}) async =>
      const AiSettings();

  @override
  Future<AiSettings> saveAiSettings(
    AiSettings settings, {
    bool admin = false,
  }) async => settings;

  @override
  Future<void> testAiSettings() async {}

  @override
  Future<void> submitFeedback({
    required String type,
    required String message,
    int? rating,
  }) async {}

  @override
  Future<List<Map<String, dynamic>>> getMyFeedback() async => [];

  @override
  Future<Map<String, dynamic>> getAdminDashboard() async => {
    'totalUsers': 1,
    'activeUsers7d': 1,
    'totalTasks': _tasks.length,
    'openComplaints': 0,
    'averageRating': 0,
    'aiRequests7d': 0,
    'averageAiLatencyMs': 0,
  };

  @override
  Future<List<Map<String, dynamic>>> getAdminUsers() async => [];

  @override
  Future<List<Map<String, dynamic>>> getAdminFeedback() async => [];

  @override
  Future<void> updateFeedbackStatus(
    String id,
    String status, {
    String adminReply = '',
  }) async {}

  @override
  void signOut() {}
}

class ApiTaskRepository implements TaskRepository {
  ApiTaskRepository(this.baseUrl, {String fallbackBaseUrl = ''})
    : _baseUrlCandidates = _buildBaseUrlCandidates(baseUrl, fallbackBaseUrl);

  final String baseUrl;
  final List<String> _baseUrlCandidates;
  final http.Client _client = http.Client();
  static const _storage = FlutterSecureStorage();
  String? accessToken;
  String? _reachableBaseUrl;

  static List<String> _buildBaseUrlCandidates(String primary, String fallback) {
    final candidates = <String>[
      primary,
      fallback,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...[
        'http://127.0.0.1:3000',
        'http://10.0.2.2:3000',
      ],
    ];
    return candidates
        .map((url) => url.trim().replaceFirst(RegExp(r'/$'), ''))
        .where((url) => url.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  Future<String> _resolveBaseUrl() async {
    if (_reachableBaseUrl != null) return _reachableBaseUrl!;

    for (final candidate in _baseUrlCandidates) {
      try {
        final response = await _client
            .get(Uri.parse('$candidate/health'))
            .timeout(const Duration(seconds: 3));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          _reachableBaseUrl = candidate;
          debugPrint('Action Planner backend selected: $candidate');
          return candidate;
        }
      } catch (error) {
        debugPrint('Action Planner backend unavailable at $candidate: $error');
      }
    }

    throw ApiException(
      'Không thể kết nối backend. Đã thử: ${_baseUrlCandidates.join(', ')}.',
    );
  }

  @override
  Future<String> checkConnection() => _resolveBaseUrl();

  Future<void> _writeToken(String token) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('access_token', token);
      return;
    }
    await _storage.write(key: 'access_token', value: token);
  }

  Future<String?> _readToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('access_token');
    }
    return _storage.read(key: 'access_token');
  }

  Future<void> _deleteToken() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('access_token');
      return;
    }
    await _storage.delete(key: 'access_token');
  }

  Future<dynamic> _request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    try {
      final selectedBaseUrl = await _resolveBaseUrl();
      final uri = Uri.parse('$selectedBaseUrl$path');
      final headers = <String, String>{'Content-Type': 'application/json'};
      if (accessToken != null) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
      final encodedBody = body == null ? null : jsonEncode(body);
      final response =
          await switch (method) {
            'POST' => _client.post(uri, headers: headers, body: encodedBody),
            'PUT' => _client.put(uri, headers: headers, body: encodedBody),
            'PATCH' => _client.patch(uri, headers: headers, body: encodedBody),
            'DELETE' => _client.delete(
              uri,
              headers: headers,
              body: encodedBody,
            ),
            _ => _client.get(uri, headers: headers),
          }.timeout(
            path.startsWith('/api/ai') || path.startsWith('/api/plans')
                ? const Duration(seconds: 120)
                : const Duration(seconds: 20),
          );
      final text = utf8.decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String? message;
        try {
          final errorBody = jsonDecode(text);
          if (errorBody is Map && errorBody['message'] != null) {
            message = '${errorBody['message']}';
          }
        } catch (_) {
          // Phản hồi không phải JSON; dùng thông báo HTTP ở dưới.
        }
        throw ApiException(
          message ?? 'Máy chủ trả về lỗi ${response.statusCode}.',
        );
      }
      return text.isEmpty ? null : jsonDecode(text);
    } on http.ClientException catch (error) {
      _reachableBaseUrl = null;
      throw ApiException('Mất kết nối tới backend: $error');
    } on TimeoutException {
      final failedBaseUrl = _reachableBaseUrl;
      _reachableBaseUrl = null;
      throw ApiException(
        'Backend phản hồi quá chậm${failedBaseUrl == null ? '' : ' tại $failedBaseUrl'}.',
      );
    }
  }

  @override
  Future<AuthenticatedUser> authenticate({
    required String name,
    required String email,
    required String password,
    required bool register,
  }) async {
    final data = await _request(
      register ? '/api/auth/register' : '/api/auth/login',
      method: 'POST',
      body: {'fullName': name, 'email': email, 'password': password},
    );
    accessToken = data['token'] as String;
    await _writeToken(accessToken!);
    final user = Map<String, dynamic>.from(data['user']);
    return AuthenticatedUser(
      id: '${user['user_id'] ?? ''}',
      fullName: '${user['full_name'] ?? name}',
      email: '${user['email'] ?? email}',
      role: '${user['role'] ?? 'user'}',
    );
  }

  @override
  Future<AuthenticatedUser?> restoreSession() async {
    try {
      accessToken = await _readToken();
      if (accessToken == null) return null;
      final user = Map<String, dynamic>.from(await _request('/api/auth/me'));
      return AuthenticatedUser(
        id: '${user['user_id'] ?? ''}',
        fullName: '${user['full_name'] ?? ''}',
        email: '${user['email'] ?? ''}',
        role: '${user['role'] ?? 'user'}',
      );
    } catch (_) {
      accessToken = null;
      try {
        await _deleteToken();
      } catch (_) {
        // Plugin storage không tồn tại trong một số môi trường test/desktop.
      }
      return null;
    }
  }

  @override
  Future<List<PlannerTask>> getTasks() async {
    final data = await _request('/api/tasks') as List;
    final result = data
        .map((item) => PlannerTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'cached_tasks',
      jsonEncode(result.map((task) => task.toJson()).toList()),
    );
    return result;
  }

  @override
  Future<List<PlannerTask>> getCachedTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cached_tasks');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => PlannerTask.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<PlannerTask> saveTask(PlannerTask task) async {
    final isNew = task.id.startsWith('local-');
    final data = await _request(
      isNew ? '/api/tasks' : '/api/tasks/${task.id}',
      method: isNew ? 'POST' : 'PUT',
      body: task.toJson(),
    );
    return PlannerTask.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> updateStatus(String id, TaskStatus status) async {
    await _request(
      '/api/tasks/$id/status',
      method: 'PATCH',
      body: {'status': status.name},
    );
  }

  @override
  Future<AiTaskAnalysis> analyzeTask(String title, String description) async {
    final data = await _request(
      '/api/ai/analyze-task',
      method: 'POST',
      body: {'title': title, 'description': description},
    );
    return AiTaskAnalysis.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<String> askAi(
    String message, {
    List<Map<String, String>> history = const [],
  }) async {
    final data = await _request(
      '/api/ai/chat',
      method: 'POST',
      body: {'message': message, 'history': history},
    );
    return data['answer'] as String;
  }

  @override
  Future<ReplanProposal> proposeReplan({String feedback = ''}) async {
    final data = await _request(
      '/api/plans/replan',
      method: 'POST',
      body: {'feedback': feedback},
    );
    final proposedTasks = (data['tasks'] as List)
        .map((item) => PlannerTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    return ReplanProposal(
      summary: '${data['summary'] ?? ''}',
      tasks: proposedTasks,
    );
  }

  @override
  Future<List<PlannerTask>> acceptReplan(ReplanProposal proposal) async {
    final data = await _request(
      '/api/plans/replan/accept',
      method: 'POST',
      body: {
        'tasks': proposal.tasks
            .map(
              (task) => {
                'id': task.id,
                'estimatedMinutes': task.estimatedMinutes,
                'aiSuggestion': task.aiSuggestion,
              },
            )
            .toList(),
      },
    ) as List;
    return data
        .map((item) => PlannerTask.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  @override
  Future<AiSettings> getAiSettings({bool admin = false}) async {
    final data = await _request(
      admin ? '/api/admin/settings/ai' : '/api/settings/ai',
    );
    return AiSettings.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<AiSettings> saveAiSettings(
    AiSettings settings, {
    bool admin = false,
  }) async {
    final data = await _request(
      admin ? '/api/admin/settings/ai' : '/api/settings/ai',
      method: 'PUT',
      body: settings.toJson(),
    );
    return AiSettings.fromJson(Map<String, dynamic>.from(data));
  }

  @override
  Future<void> testAiSettings() async {
    await _request('/api/settings/ai/test', method: 'POST');
  }

  @override
  Future<void> submitFeedback({
    required String type,
    required String message,
    int? rating,
  }) async {
    await _request(
      '/api/feedback',
      method: 'POST',
      body: {'type': type, 'message': message, 'rating': rating},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getMyFeedback() async =>
      (await _request('/api/feedback') as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  @override
  Future<Map<String, dynamic>> getAdminDashboard() async =>
      Map<String, dynamic>.from(await _request('/api/admin/dashboard'));

  @override
  Future<List<Map<String, dynamic>>> getAdminUsers() async =>
      (await _request('/api/admin/users') as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  @override
  Future<List<Map<String, dynamic>>> getAdminFeedback() async =>
      (await _request('/api/admin/feedback') as List)
          .map((item) => Map<String, dynamic>.from(item))
          .toList();

  @override
  Future<void> updateFeedbackStatus(
    String id,
    String status, {
    String adminReply = '',
  }) async {
    await _request(
      '/api/admin/feedback/$id',
      method: 'PATCH',
      body: {'status': status, 'adminReply': adminReply},
    );
  }

  @override
  void signOut() {
    accessToken = null;
    unawaited(_deleteToken());
  }
}
