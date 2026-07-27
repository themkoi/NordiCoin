String formatTimeAgo(DateTime time) {
  final now = DateTime.now();
  final difference = now.difference(time);

  if (difference.inSeconds < 60) {
    return '${difference.inSeconds}s ago';
  } else if (difference.inMinutes < 60) {
    final mins = difference.inMinutes;
    final secs = difference.inSeconds % 60;
    return secs > 0 ? '${mins}m ${secs}s ago' : '${mins}m ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    final mins = (difference.inMinutes % 60);
    return mins > 0 ? '${hours}h ${mins}m ago' : '${hours}h ago';
  } else {
    final days = difference.inDays;
    final hours = (difference.inHours % 24);
    return hours > 0 ? '${days}d ${hours}h ago' : '${days}d ago';
  }
}

String formatMinutes(int minutes) {
  if (minutes < 1) return '0m';

  final years = minutes ~/ 525600;
  final days = (minutes % 525600) ~/ 1440;
  final hours = (minutes % 1440) ~/ 60;
  final mins = minutes % 60;

  final parts = <String>[];
  if (years > 0) parts.add('${years}y');
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  if (mins > 0) parts.add('${mins}m');

  return parts.join(' ');
}
