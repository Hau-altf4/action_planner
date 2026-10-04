class ScheduleItem {
  const ScheduleItem({
    required this.taskId,
    required this.title,
    required this.start,
    required this.end,
  });

  final String taskId;
  final String title;
  final DateTime start;
  final DateTime end;
}
