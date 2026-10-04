import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/task.dart';
import '../state/app_state.dart';
import '../services/notification_service.dart';
import 'admin_page.dart';
import 'feedback_page.dart';
import 'settings_page.dart';
import 'task_editor.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.appState});

  final AppState appState;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  Timer? _deadlineTimer;

  @override
  void initState() {
    super.initState();
    _deadlineTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _deadlineTimer?.cancel();
    super.dispose();
  }

  Future<void> _addTask() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => TaskEditorPage(appState: widget.appState),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardView(appState: widget.appState, onAdd: _addTask),
      TasksView(appState: widget.appState),
      ScheduleView(appState: widget.appState),
      AiView(appState: widget.appState),
      ProfileView(appState: widget.appState),
    ];
    final titles = [
      'Hôm nay',
      'Công việc',
      'Lịch trình',
      'Trợ lý AI',
      'Cá nhân',
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_index]),
        actions: [
          if (_index < 3)
            IconButton(
              onPressed: widget.appState.load,
              tooltip: 'Làm mới',
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: widget.appState.isLoading && widget.appState.tasks.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : IndexedStack(index: _index, children: pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: _addTask,
              icon: const Icon(Icons.add),
              label: const Text('Thêm task'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.today_outlined),
            label: 'Hôm nay',
          ),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Task'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            label: 'Lịch',
          ),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: 'AI'),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Cá nhân',
          ),
        ],
      ),
    );
  }
}

class DashboardView extends StatelessWidget {
  const DashboardView({super.key, required this.appState, required this.onAdd});

  final AppState appState;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final completed = appState.tasks
        .where((t) => t.status == TaskStatus.completed)
        .length;
    final progress = appState.tasks.isEmpty
        ? 0.0
        : completed / appState.tasks.length;
    final active = appState.tasks
        .where((t) => t.status != TaskStatus.completed)
        .toList();
    return RefreshIndicator(
      onRefresh: appState.load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
        children: [
          Text(
            'Chào ${appState.userName} 👋',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text('Hãy biến kế hoạch hôm nay thành kết quả.'),
          const SizedBox(height: 20),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tiến độ hôm nay',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text('$completed/${appState.tasks.length} task'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 9,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(height: 10),
                  Text('${(progress * 100).round()}% đã hoàn thành'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Ưu tiên tiếp theo',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Thêm'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (active.isEmpty)
            const _EmptyState(message: 'Bạn đã hoàn thành tất cả công việc!')
          else
            ...active.map(
              (task) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: TaskCard(task: task, appState: appState),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context)
                    .colorScheme
                    .secondaryContainer,
                child: const Icon(Icons.auto_awesome),
              ),
              title: const Text(
                'Gợi ý thông minh',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Bắt đầu với công việc khẩn cấp, sau đó nghỉ 10 phút trước phiên tiếp theo.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class TasksView extends StatefulWidget {
  const TasksView({super.key, required this.appState});

  final AppState appState;

  @override
  State<TasksView> createState() => _TasksViewState();
}

class _TasksViewState extends State<TasksView> {
  TaskStatus? filter;

  @override
  Widget build(BuildContext context) {
    final tasks = filter == null
        ? widget.appState.tasks
        : widget.appState.tasks.where((task) => task.status == filter).toList();
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Tất cả'),
                selected: filter == null,
                onSelected: (_) => setState(() => filter = null),
              ),
              const SizedBox(width: 8),
              ...TaskStatus.values.map(
                (status) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(status.label),
                    selected: filter == status,
                    onSelected: (_) => setState(() => filter = status),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: tasks.isEmpty
              ? const _EmptyState(message: 'Không có công việc trong nhóm này.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: tasks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, index) =>
                      TaskCard(task: tasks[index], appState: widget.appState),
                ),
        ),
      ],
    );
  }
}

class TaskCard extends StatelessWidget {
  const TaskCard({super.key, required this.task, required this.appState});

  final PlannerTask task;
  final AppState appState;

  Color _priorityColor() => switch (task.priority) {
    TaskPriority.low => Colors.blue,
    TaskPriority.medium => Colors.amber.shade800,
    TaskPriority.high => Colors.deepOrange,
    TaskPriority.urgent => Colors.red,
  };

  String _deadlineLabel() {
    final deadline = task.deadline.toLocal();
    final difference = deadline.difference(DateTime.now());
    if (difference.isNegative) {
      final overdue = difference.abs();
      if (overdue.inDays > 0) return 'Quá hạn ${overdue.inDays} ngày';
      if (overdue.inHours > 0) return 'Quá hạn ${overdue.inHours} giờ';
      return 'Vừa quá hạn';
    }
    if (difference.inDays > 0) return 'Còn ${difference.inDays} ngày';
    if (difference.inHours > 0) return 'Còn ${difference.inHours} giờ';
    return 'Còn ${difference.inMinutes.clamp(0, 59)} phút';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDetails(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: task.status == TaskStatus.completed,
                    onChanged: (value) => appState.setStatus(
                      task,
                      value == true ? TaskStatus.completed : TaskStatus.pending,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${task.category} • ${task.estimatedMinutes} phút',
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _deadlineLabel(),
                          style: TextStyle(
                            color: task.deadline.isBefore(DateTime.now())
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _priorityColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              if (task.progress > 0) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: task.progress),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TaskEditorPage(appState: appState, task: task),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              task.description.isEmpty ? 'Chưa có mô tả.' : task.description,
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(task.category)),
                Chip(label: Text('Ưu tiên: ${task.priority.label}')),
                Chip(label: Text('${task.estimatedMinutes} phút')),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Các bước thực hiện',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            if (task.steps.isEmpty)
              const Text('AI có thể giúp bạn chia nhỏ công việc này.')
            else
              ...task.steps.map(
                (step) => CheckboxListTile(
                  value: step.isCompleted,
                  contentPadding: EdgeInsets.zero,
                  title: Text(step.title),
                  onChanged: (value) =>
                      appState.toggleStep(task, step, value ?? false),
                ),
              ),
            if (task.aiSuggestion != null) ...[
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome),
                title: const Text('Gợi ý AI'),
                subtitle: Text(task.aiSuggestion!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _PlanDecision { accept, revise }

class ScheduleView extends StatelessWidget {
  const ScheduleView({super.key, required this.appState});
  final AppState appState;

  String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Future<String?> _askFeedback(BuildContext context) async {
    final controller = TextEditingController();
    final feedback = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Bạn muốn điều chỉnh thế nào?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          autocorrect: true,
          enableSuggestions: true,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText:
                'Ví dụ: ưu tiên việc ngắn trước hoặc dành buổi sáng để học…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              controller.text.trim().isEmpty
                  ? 'Hãy đề xuất một phương án khác.'
                  : controller.text.trim(),
            ),
            child: const Text('Tạo phương án khác'),
          ),
        ],
      ),
    );
    // showDialog completes as soon as Navigator.pop is called, while the route
    // still needs a short reverse transition before its inherited widgets can
    // be safely removed and another dialog/state rebuild can begin.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    return feedback;
  }

  Future<void> _startReplan(BuildContext context) async {
    var feedback = '';
    while (context.mounted) {
      ReplanProposal proposal;
      try {
        proposal = await appState.proposeReplan(feedback: feedback);
      } catch (exception) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Không thể tạo kế hoạch: $exception')),
          );
        }
        return;
      }
      if (!context.mounted) return;

      final decision = await showDialog<_PlanDecision>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Phương án AI đề xuất'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(proposal.summary),
                  const SizedBox(height: 16),
                  ...proposal.tasks.indexed.map(
                    (entry) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(child: Text('${entry.$1 + 1}')),
                      title: Text(entry.$2.title),
                      subtitle: entry.$2.aiSuggestion == null
                          ? null
                          : Text(entry.$2.aiSuggestion!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Cách sắp xếp này có hợp lý với bạn không?'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _PlanDecision.revise),
              child: const Text('Chưa hợp lý'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _PlanDecision.accept),
              child: const Text('Áp dụng'),
            ),
          ],
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!context.mounted) return;

      if (decision == _PlanDecision.accept) {
        try {
          await appState.acceptReplan(proposal);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã áp dụng kế hoạch mới.')),
            );
          }
        } catch (exception) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Không thể lưu kế hoạch: $exception')),
            );
          }
        }
        return;
      }
      if (decision != _PlanDecision.revise || !context.mounted) return;
      final nextFeedback = await _askFeedback(context);
      if (nextFeedback == null) return;
      final rejectedOrder = proposal.tasks.map((task) => task.id).join(',');
      feedback = '$nextFeedback\nREJECTED_ORDER:$rejectedOrder';
    }
  }

  @override
  Widget build(BuildContext context) {
    final schedule = appState.schedule;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'AI sẽ đề xuất lịch và chỉ áp dụng sau khi bạn xác nhận.',
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: appState.isLoading
                      ? null
                      : () => _startReplan(context),
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Đề xuất'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (schedule.isEmpty)
          const _EmptyState(message: 'Chưa có công việc cần xếp lịch.')
        else
          ...schedule.map((item) {
            final overdue = item.end.isBefore(DateTime.now());
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      _time(item.start),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  VerticalDivider(
                    color: Theme.of(context).colorScheme.primary,
                    thickness: 3,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8, bottom: 22),
                      child: Card(
                        child: ListTile(
                          title: Text(item.title),
                          subtitle: Text(
                            '${_time(item.start)} – ${_time(item.end)}'
                            '${overdue ? '  •  Đã quá lịch' : ''}',
                            style: overdue
                                ? TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  )
                                : null,
                          ),
                          leading: Icon(
                            overdue
                                ? Icons.warning_amber_rounded
                                : Icons.schedule,
                            color: overdue
                                ? Theme.of(context).colorScheme.error
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

class AiView extends StatefulWidget {
  const AiView({super.key, required this.appState});
  final AppState appState;

  @override
  State<AiView> createState() => _AiViewState();
}

class _AiViewState extends State<AiView> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = controller.text;
    controller.clear();
    widget.appState.askAi(text);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount:
                widget.appState.messages.length +
                (widget.appState.isAiBusy ? 1 : 0),
            itemBuilder: (_, index) {
              if (index == widget.appState.messages.length) {
                return const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final message = widget.appState.messages[index];
              return Align(
                alignment: message.fromUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 520),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: message.fromUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(message.text),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                    autocorrect: true,
                    enableSuggestions: true,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Hỏi AI hoặc yêu cầu chia nhỏ task...',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: widget.appState.isAiBusy ? null : _send,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ProfileView extends StatelessWidget {
  const ProfileView({super.key, required this.appState});
  final AppState appState;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 44)),
        const SizedBox(height: 12),
        Text(
          appState.userName,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(appState.userEmail, textAlign: TextAlign.center),
        const SizedBox(height: 28),
        Card(
          child: Column(
            children: [
              if (kIsWeb)
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Bật nhắc deadline trên web'),
                  subtitle: const Text(
                    'Bật âm báo, nhắc trước 10 phút và báo ngay khi quá hạn.',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final granted = await NotificationService.instance
                        .requestPermission();
                    await NotificationService.instance.rescheduleAll(
                      appState.tasks,
                    );
                    await NotificationService.instance.showTestNotification();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            granted
                                ? 'Đã bật nhắc deadline. Một thông báo thử vừa được phát.'
                                : 'Không thể bật thông báo trên thiết bị này.',
                          ),
                        ),
                      );
                    }
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Bật thông báo deadline'),
                  subtitle: const Text('Nhắc trước 10 phút và báo quá hạn'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final granted = await NotificationService.instance
                        .requestPermission();
                    if (granted) {
                      await NotificationService.instance.rescheduleAll(
                        appState.tasks,
                      );
                      await NotificationService.instance.showTestNotification();
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            granted
                                ? 'Đã bật và lên lịch thông báo.'
                                : 'Bạn chưa cấp quyền thông báo.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Cài đặt AI'),
                subtitle: const Text('Ollama, OpenAI, Gemini hoặc Claude'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AiSettingsPage(appState: appState),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.feedback_outlined),
                title: const Text('Đề xuất, đánh giá & khiếu nại'),
                subtitle: const Text('Xem trạng thái và câu trả lời từ admin'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FeedbackPage(appState: appState),
                  ),
                ),
              ),
              if (appState.isAdmin) ...[
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings_outlined),
                  title: const Text('Dashboard quản trị'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminPage(appState: appState),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: appState.signOut,
          icon: const Icon(Icons.logout),
          label: const Text('Đăng xuất'),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      children: [
        Icon(
          Icons.inbox_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
      ],
    ),
  );
}
