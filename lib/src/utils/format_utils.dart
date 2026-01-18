/// Formats a size in kilobytes to a human-readable string
String formatSize(int sizeInKB) {
  if (sizeInKB >= 1024 * 1024) {
    return '${(sizeInKB / (1024 * 1024)).toStringAsFixed(1)} GB';
  } else if (sizeInKB >= 1024) {
    return '${(sizeInKB / 1024).toStringAsFixed(1)} MB';
  }
  return '$sizeInKB KB';
}

/// Formats a duration to a human-readable string
String formatDuration(Duration duration) {
  if (duration.inSeconds < 1) {
    return '${duration.inMilliseconds}ms';
  } else if (duration.inMinutes < 1) {
    return '${duration.inSeconds}s';
  }
  return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

/// Truncates a path for display, keeping the last N components
String truncatePath(String path, {int maxLength = 60}) {
  if (path.length <= maxLength) return path;
  return '...${path.substring(path.length - maxLength + 3)}';
}
