import 'dart:io';

import '../models/build_directory.dart';
import '../utils/platform_utils.dart';

/// Result of a clean operation
class CleanResult {
  const CleanResult({
    required this.successful,
    required this.failed,
    required this.totalSize,
  });

  final List<BuildDirectory> successful;
  final List<BuildDirectory> failed;
  final int totalSize;

  int get successCount => successful.length;
  int get failCount => failed.length;
  int get totalCount => successCount + failCount;
}

/// Abstract cleaner interface
abstract class Cleaner {
  /// Moves a directory to trash (recoverable)
  Future<bool> moveToTrash(String path);

  /// Permanently deletes a directory
  Future<bool> permanentDelete(String path);

  /// Cleans multiple directories
  Future<CleanResult> cleanDirectories(
    List<BuildDirectory> directories, {
    bool permanent = false,
  }) async {
    final successful = <BuildDirectory>[];
    final failed = <BuildDirectory>[];
    int totalSize = 0;

    for (final dir in directories) {
      bool success;
      if (permanent) {
        success = await permanentDelete(dir.path);
      } else {
        success = await moveToTrash(dir.path);
      }

      if (success) {
        successful.add(dir);
        totalSize += dir.sizeInKB;
      } else {
        failed.add(dir);
      }
    }

    return CleanResult(
      successful: successful,
      failed: failed,
      totalSize: totalSize,
    );
  }
}

/// macOS-specific cleaner using Finder
class MacOSCleaner extends Cleaner {
  @override
  Future<bool> moveToTrash(String path) async {
    final process = await Process.run(
      'osascript',
      ['-e', 'tell application "Finder" to delete POSIX file "$path"'],
    );
    return process.exitCode == 0;
  }

  @override
  Future<bool> permanentDelete(String path) async {
    return _deleteWithRm(path);
  }
}

/// Linux-specific cleaner using gio or trash-cli
class LinuxCleaner extends Cleaner {
  @override
  Future<bool> moveToTrash(String path) async {
    // Try gio first (GNOME)
    var process = await Process.run('gio', ['trash', path]);
    if (process.exitCode == 0) return true;

    // Fallback to trash-cli
    process = await Process.run('trash-put', [path]);
    if (process.exitCode == 0) return true;

    // If no trash available, warn and fail
    return false;
  }

  @override
  Future<bool> permanentDelete(String path) async {
    return _deleteWithRm(path);
  }
}

/// Windows-specific cleaner
class WindowsCleaner extends Cleaner {
  @override
  Future<bool> moveToTrash(String path) async {
    // Windows doesn't have easy trash access from command line
    // Use PowerShell to move to recycle bin
    final process = await Process.run(
      'powershell',
      [
        '-Command',
        '''
        Add-Type -AssemblyName Microsoft.VisualBasic
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory('$path', 'OnlyErrorDialogs', 'SendToRecycleBin')
        '''
      ],
    );
    return process.exitCode == 0;
  }

  @override
  Future<bool> permanentDelete(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }
}

/// Factory to create the appropriate cleaner for the current platform
Cleaner createCleaner() {
  switch (getCurrentPlatform()) {
    case SupportedPlatform.macOS:
      return MacOSCleaner();
    case SupportedPlatform.linux:
      return LinuxCleaner();
    case SupportedPlatform.windows:
      return WindowsCleaner();
    case SupportedPlatform.unknown:
      return LinuxCleaner(); // Fallback
  }
}

/// Helper to delete with rm -rf (Unix)
Future<bool> _deleteWithRm(String path) async {
  final platform = getCurrentPlatform();
  if (platform == SupportedPlatform.windows) {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  final process = await Process.run('rm', ['-rf', path]);
  return process.exitCode == 0;
}
