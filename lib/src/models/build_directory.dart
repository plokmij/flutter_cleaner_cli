/// Represents a build directory found during scanning
class BuildDirectory {
  const BuildDirectory({
    required this.path,
    required this.sizeInKB,
    this.isSelected = false,
  });

  /// The full path to the build directory
  final String path;

  /// Size in kilobytes
  final int sizeInKB;

  /// Whether this directory is selected for deletion
  final bool isSelected;

  /// Size in bytes
  int get sizeInBytes => sizeInKB * 1024;

  /// Size in megabytes (as double for precision)
  double get sizeInMB => sizeInKB / 1024;

  /// Human-readable size string
  String get formattedSize {
    if (sizeInKB >= 1024 * 1024) {
      return '${(sizeInKB / (1024 * 1024)).toStringAsFixed(1)} GB';
    } else if (sizeInKB >= 1024) {
      return '${(sizeInKB / 1024).toStringAsFixed(1)} MB';
    }
    return '$sizeInKB KB';
  }

  BuildDirectory copyWith({
    String? path,
    int? sizeInKB,
    bool? isSelected,
  }) {
    return BuildDirectory(
      path: path ?? this.path,
      sizeInKB: sizeInKB ?? this.sizeInKB,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BuildDirectory &&
        other.path == path &&
        other.sizeInKB == sizeInKB &&
        other.isSelected == isSelected;
  }

  @override
  int get hashCode => path.hashCode ^ sizeInKB.hashCode ^ isSelected.hashCode;

  @override
  String toString() =>
      'BuildDirectory(path: $path, size: $formattedSize, selected: $isSelected)';
}
