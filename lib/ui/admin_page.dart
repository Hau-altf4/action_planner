import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'settings_page.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  Map<String, dynamic>? _metrics;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _feedback = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        widget.appState.repository.getAdminDashboard(),
        widget.appState.repository.getAdminUsers(),
        widget.appState.repository.getAdminFeedback(),
      ]);
      if (!mounted) return;
      setState(() {
        _metrics = results[0] as Map<String, dynamic>;
        _users = results[1] as List<Map<String, dynamic>>;
        _feedback = results[2] as List<Map<String, dynamic>>;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    final date = DateTime.tryParse('$raw')?.toLocal();
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Future<void> _reply(Map<String, dynamic> item) async {
    final controller = TextEditingController(
      text: '${item['adminReply'] ?? ''}',
    );
    var status = item['status'] == 'resolved' ? 'resolved' : 'inProgress';
    var saving = false;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: !saving,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Trả lời người dùng'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 2000,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung trả lời',
                    hintText: 'Nhập câu trả lời để gửi đến người dùng…',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Trạng thái'),
                  items: const [
                    DropdownMenuItem(
                      value: 'inProgress',
                      child: Text('Đang xử lý'),
                    ),
                    DropdownMenuItem(
                      value: 'resolved',
                      child: Text('Đã giải quyết'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) => setDialogState(() => status = value!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final reply = controller.text.trim();
                      if (reply.isEmpty) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text('Vui lòng nhập nội dung trả lời.'),
                          ),
                        );
                        return;
                      }
                      setDialogState(() => saving = true);
                      try {
                        await widget.appState.repository.updateFeedbackStatus(
                          '${item['id']}',
                          status,
                          adminReply: reply,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        setDialogState(() => saving = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text('Không thể trả lời: $error'),
                            ),
                          );
                        }
                      }
                    },
              icon: const Icon(Icons.send_outlined),
              label: Text(saving ? 'Đang gửi…' : 'Gửi trả lời'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (saved == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi câu trả lời đến người dùng.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản trị hệ thống'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Không thể tải dashboard: $_error'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Metric(
                        'Người dùng',
                        '${_metrics?['totalUsers'] ?? 0}',
                        Icons.people,
                      ),
                      _Metric(
                        'Hoạt động 7 ngày',
                        '${_metrics?['activeUsers7d'] ?? 0}',
                        Icons.bolt,
                      ),
                      _Metric(
                        'Công việc',
                        '${_metrics?['totalTasks'] ?? 0}',
                        Icons.task_alt,
                      ),
                      _Metric(
                        'Khiếu nại mở',
                        '${_metrics?['openComplaints'] ?? 0}',
                        Icons.report_outlined,
                      ),
                      _Metric(
                        'Đánh giá',
                        (num.tryParse('${_metrics?['averageRating'] ?? 0}') ??
                                0)
                            .toStringAsFixed(1),
                        Icons.star_outline,
                      ),
                      _Metric(
                        'AI / 7 ngày',
                        '${_metrics?['aiRequests7d'] ?? 0}',
                        Icons.auto_awesome,
                      ),
                      _Metric(
                        'Độ trễ AI',
                        '${_metrics?['averageAiLatencyMs'] ?? 0} ms',
                        Icons.speed,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('Cấu hình AI mặc định'),
                      subtitle: const Text(
                        'Áp dụng cho user không dùng API riêng',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AiSettingsPage(
                            appState: widget.appState,
                            admin: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Phản hồi & khiếu nại',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  if (_feedback.isEmpty)
                    const Text('Chưa có phản hồi.')
                  else
                    ..._feedback.map((item) {
                      final user = item['user'] as Map?;
                      final reply = '${item['adminReply'] ?? ''}'.trim();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    item['type'] == 'complaint'
                                        ? Icons.report
                                        : Icons.chat_outlined,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      '${item['message']}'.isEmpty
                                          ? 'Đánh giá ${item['rating']}/5'
                                          : '${item['message']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${user?['email'] ?? 'Không rõ'} • ${_date(item['createdAt'])} • ${item['status']}',
                              ),
                              if (reply.isNotEmpty) ...[
                                const Divider(height: 24),
                                Text(
                                  'Đã trả lời: $reply',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ],
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonalIcon(
                                  onPressed: () => _reply(item),
                                  icon: Icon(
                                    reply.isEmpty
                                        ? Icons.reply
                                        : Icons.edit_outlined,
                                  ),
                                  label: Text(
                                    reply.isEmpty
                                        ? 'Trả lời user'
                                        : 'Sửa câu trả lời',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 24),
                  Text(
                    'Tài khoản gần đây',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  ..._users.map(
                    (user) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(
                            '${user['full_name'] ?? '?'}'.characters.first,
                          ),
                        ),
                        title: Text('${user['full_name'] ?? ''}'),
                        subtitle: Text(
                          '${user['email']} • tham gia ${_date(user['createdAt'])}',
                        ),
                        trailing: Text('${user['role'] ?? 'user'}'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 168,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(label),
          ],
        ),
      ),
    ),
  );
}
