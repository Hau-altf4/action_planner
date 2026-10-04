import 'package:flutter/material.dart';

import '../state/app_state.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.appState});

  final AppState appState;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  List<Map<String, dynamic>> _items = [];
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
      final items = await widget.appState.repository.getMyFeedback();
      if (mounted) setState(() => _items = items);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _date(dynamic raw) {
    final date = DateTime.tryParse('$raw')?.toLocal();
    if (date == null) return '—';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _type(dynamic type) => switch ('$type') {
    'complaint' => 'Khiếu nại',
    'rating' => 'Đánh giá',
    _ => 'Đề xuất',
  };

  String _status(dynamic status) => switch ('$status') {
    'resolved' => 'Đã trả lời',
    'inProgress' => 'Đang xử lý',
    _ => 'Đã tiếp nhận',
  };

  Future<void> _compose() async {
    final controller = TextEditingController();
    var type = 'suggestion';
    var rating = 5;
    var sending = false;
    final sent = await showDialog<bool>(
      context: context,
      barrierDismissible: !sending,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Gửi phản hồi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Loại phản hồi'),
                  items: const [
                    DropdownMenuItem(
                      value: 'suggestion',
                      child: Text('Đề xuất'),
                    ),
                    DropdownMenuItem(
                      value: 'complaint',
                      child: Text('Khiếu nại'),
                    ),
                    DropdownMenuItem(value: 'rating', child: Text('Đánh giá')),
                  ],
                  onChanged: sending
                      ? null
                      : (value) => setDialogState(() => type = value!),
                ),
                const SizedBox(height: 12),
                if (type == 'rating')
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      5,
                      (index) => IconButton(
                        onPressed: sending
                            ? null
                            : () => setDialogState(() => rating = index + 1),
                        icon: Icon(
                          index < rating ? Icons.star : Icons.star_border,
                        ),
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ),
                TextField(
                  controller: controller,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Nội dung',
                    hintText: 'Mô tả đề xuất hoặc vấn đề bạn gặp phải…',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: sending
                  ? null
                  : () async {
                      setDialogState(() => sending = true);
                      try {
                        await widget.appState.submitFeedback(
                          type: type,
                          message: controller.text.trim(),
                          rating: type == 'rating' ? rating : null,
                        );
                        if (dialogContext.mounted)
                          Navigator.pop(dialogContext, true);
                      } catch (error) {
                        setDialogState(() => sending = false);
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('Không thể gửi: $error')),
                          );
                        }
                      }
                    },
              child: Text(sending ? 'Đang gửi…' : 'Gửi'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (sent == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi phản hồi đến quản trị viên.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phản hồi của tôi'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Gửi phản hồi'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Không thể tải phản hồi: $_error'))
          : _items.isEmpty
          ? const Center(child: Text('Bạn chưa gửi phản hồi nào.'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final reply = '${item['adminReply'] ?? ''}'.trim();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _type(item['type']),
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              Chip(label: Text(_status(item['status']))),
                            ],
                          ),
                          if (item['rating'] != null)
                            Text('Đánh giá: ${item['rating']}/5'),
                          if ('${item['message'] ?? ''}'.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('${item['message']}'),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            'Đã gửi ${_date(item['createdAt'])}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          if (reply.isNotEmpty) ...[
                            const Divider(height: 28),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.support_agent, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Phản hồi từ quản trị viên',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(reply),
                                      const SizedBox(height: 4),
                                      Text(
                                        _date(item['repliedAt']),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
