import 'dart:io';

/// Enum representing supported platforms
enum SupportedPlatform {
  macOS,
  linux,
  windows,
  unknown,
}

/// Gets the current platform
SupportedPlatform getCurrentPlatform() {
  if (Platform.isMacOS) return SupportedPlatform.macOS;
  if (Platform.isLinux) return SupportedPlatform.linux;
  if (Platform.isWindows) return SupportedPlatform.windows;
  return SupportedPlatform.unknown;
}

/// Returns true if the current platform supports trash operations
bool supportsTrash() {
  final platform = getCurrentPlatform();
  return platform == SupportedPlatform.macOS ||
      platform == SupportedPlatform.linux;
}

/// Gets the home directory path
String getHomeDirectory() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  return home ?? '.';
}

/// Expands ~ to the home directory in a path
String expandPath(String path) {
  if (path.startsWith('~/')) {
    return path.replaceFirst('~', getHomeDirectory());
  }
  return path;
}
