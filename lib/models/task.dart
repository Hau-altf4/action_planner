enum TaskPriority { low, medium, high, urgent }

enum TaskStatus { pending, inProgress, completed }

class AiTaskAnalysis {
  const AiTaskAnalysis({
    required this.priority,
    required this.estimatedMinutes,
    required this.steps,
    required this.suggestion,
  });

  final TaskPriority priority;
  final int estimatedMinutes;
  final List<String> steps;
  final String suggestion;

  factory AiTaskAnalysis.fromJson(Map<String, dynamic> json) => AiTaskAnalysis(
    priority: TaskPriority.values.firstWhere(
      (item) => item.name == json['priority'],
      orElse: () => TaskPriority.medium,
    ),
    estimatedMinutes: (json['estimatedMinutes'] as num?)?.round() ?? 30,
    steps: ((json['steps'] as List?) ?? const []).cast<String>(),
    suggestion: '${json['suggestion'] ?? ''}',
  );
}

class ReplanProposal {
  const ReplanProposal({required this.summary, required this.tasks});

  final String summary;
  final List<PlannerTask> tasks;
}

class TaskStep {
  TaskStep({required this.id, required this.title, this.isCompleted = false});

  final String id;
  final String title;
  bool isCompleted;

  factory TaskStep.fromJson(Map<String, dynamic> json) => TaskStep(
    id: '${json['id'] ?? json['step_id']}',
    title: '${json['title'] ?? json['step_title'] ?? ''}',
    isCompleted: json['isCompleted'] == true || json['status'] == 'completed',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': isCompleted ? 'completed' : 'pending',
  };
}

class PlannerTask {
  PlannerTask({
    required this.id,
    required this.title,
    this.description = '',
    this.category = 'Cá nhân',
    this.priority = TaskPriority.medium,
    this.status = TaskStatus.pending,
    required this.estimatedMinutes,
    required this.deadline,
    this.scheduledStart,
    List<TaskStep>? steps,
    this.aiSuggestion,
  }) : steps = steps ?? [];

  final String id;
  String title;
  String description;
  String category;
  TaskPriority priority;
  TaskStatus status;
  int estimatedMinutes;
  DateTime deadline;
  DateTime? scheduledStart;
  final List<TaskStep> steps;
  String? aiSuggestion;

  double get progress {
    if (status == TaskStatus.completed) return 1;
    if (steps.isEmpty) return status == TaskStatus.inProgress ? .35 : 0;
    return steps.where((step) => step.isCompleted).length / steps.length;
  }

  factory PlannerTask.fromJson(Map<String, dynamic> json) {
    final rawPriority = json['priority'];
    final priority = rawPriority is int
        ? TaskPriority.values[rawPriority.clamp(0, 3)]
        : TaskPriority.values.firstWhere(
            (item) => item.name.toLowerCase() == '$rawPriority'.toLowerCase(),
            orElse: () => TaskPriority.medium,
          );
    final status = TaskStatus.values.firstWhere(
      (item) => item.name.toLowerCase() == '${json['status']}'.toLowerCase(),
      orElse: () => TaskStatus.pending,
    );
    return PlannerTask(
      id: '${json['id'] ?? json['task_id']}',
      title: '${json['title'] ?? ''}',
      description: '${json['description'] ?? ''}',
      category: '${json['category'] ?? 'Cá nhân'}',
      priority: priority,
      status: status,
      estimatedMinutes:
          (json['estimatedMinutes'] ?? json['estimated_time'] ?? 30) as int,
      deadline:
          DateTime.tryParse('${json['deadline']}')?.toLocal() ?? DateTime.now(),
      scheduledStart: DateTime.tryParse('${json['scheduledStart']}')?.toLocal(),
      steps: ((json['steps'] as List?) ?? const [])
          .map((item) => TaskStep.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      aiSuggestion: json['aiSuggestion'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'category': category,
    'priority': priority.name,
    'status': status.name,
    'estimatedMinutes': estimatedMinutes,
    'deadline': deadline.toIso8601String(),
    'scheduledStart': scheduledStart?.toIso8601String(),
    'steps': steps.map((item) => item.toJson()).toList(),
    'aiSuggestion': aiSuggestion,
  };
}

extension TaskPriorityLabel on TaskPriority {
  String get label => switch (this) {
    TaskPriority.low => 'Thấp',
    TaskPriority.medium => 'Trung bình',
    TaskPriority.high => 'Cao',
    TaskPriority.urgent => 'Khẩn cấp',
  };
}

extension TaskStatusLabel on TaskStatus {
  String get label => switch (this) {
    TaskStatus.pending => 'Chưa làm',
    TaskStatus.inProgress => 'Đang làm',
    TaskStatus.completed => 'Hoàn thành',
  };
}
