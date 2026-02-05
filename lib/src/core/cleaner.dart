import 'dart:io';

import 'package:path/path.dart' as p;

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

  /// Deletes a previously trashed item from trash by its original path
  Future<bool> deleteFromTrash(String originalPath);

  /// Empties the system trash
  Future<bool> emptyTrash();

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
  Future<bool> deleteFromTrash(String originalPath) async {
    final basename = p.basename(originalPath);
    final home = Platform.environment['HOME']!;
    final trashDir = p.join(home, '.Trash');

    // Finder may rename duplicates (e.g. "build 2"), so find all matches
    try {
      final dir = Directory(trashDir);
      if (!dir.existsSync()) return false;

      final matches = dir.listSync().where((e) {
        final name = p.basename(e.path);
        return name == basename || name.startsWith('$basename ');
      });

      if (matches.isEmpty) return true; // already gone

      for (final match in matches) {
        await Process.run('rm', ['-rf', match.path]);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> emptyTrash() async {
    final process = await Process.run(
      'osascript',
      ['-e', 'tell application "Finder" to empty trash'],
    );
    return process.exitCode == 0;
  }

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
  Future<bool> emptyTrash() async {
    // Try gio first
    var process = await Process.run('gio', ['trash', '--empty']);
    if (process.exitCode == 0) return true;

    // Fallback: manually remove trash contents
    final home = Platform.environment['HOME']!;
    final trashFiles = p.join(home, '.local', 'share', 'Trash', 'files');
    final trashInfo = p.join(home, '.local', 'share', 'Trash', 'info');
    await Process.run('rm', ['-rf', trashFiles]);
    await Process.run('rm', ['-rf', trashInfo]);
    await Directory(trashFiles).create(recursive: true);
    await Directory(trashInfo).create(recursive: true);
    return true;
  }

  @override
  Future<bool> deleteFromTrash(String originalPath) async {
    final basename = p.basename(originalPath);
    final home = Platform.environment['HOME']!;
    final filePath = p.join(home, '.local', 'share', 'Trash', 'files', basename);
    final infoPath = p.join(home, '.local', 'share', 'Trash', 'info', '$basename.trashinfo');
    final result = await Process.run('rm', ['-rf', filePath]);
    await Process.run('rm', ['-f', infoPath]);
    return result.exitCode == 0;
  }

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
  Future<bool> emptyTrash() async {
    return false; // Not supported on Windows
  }

  @override
  Future<bool> deleteFromTrash(String originalPath) async {
    return false;
  }

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
