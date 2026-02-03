import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/build_directory.dart';
import '../utils/platform_utils.dart';

/// Callback for reporting scan progress
typedef ScanProgressCallback = void Function(String currentPath);

/// Configuration for directory scanning
class ScanConfig {
  const ScanConfig({
    this.patterns = const ['build'],
    this.excludePatterns = const [],
    this.minSizeKB,
    this.includeDartTool = false,
  });

  /// Folder name patterns to search for
  final List<String> patterns;

  /// Patterns to exclude from scanning
  final List<String> excludePatterns;

  /// Minimum size in KB to include in results
  final int? minSizeKB;

  /// Whether to include .dart_tool directories
  final bool includeDartTool;

  /// Get all patterns including .dart_tool if enabled
  List<String> get allPatterns {
    final result = List<String>.from(patterns);
    if (includeDartTool) {
      result.add('.dart_tool');
    }
    return result;
  }
}

/// Scans directories for build folders
class Scanner {
  Scanner({this.config = const ScanConfig()});

  final ScanConfig config;

  /// Scans the given directory for build folders
  /// Optionally accepts a progress callback to report current scanning path
  Future<List<BuildDirectory>> scan(
    String directoryPath, {
    ScanProgressCallback? onProgress,
  }) async {
    final expandedPath = expandPath(directoryPath);
    final dir = Directory(expandedPath);

    if (!await dir.exists()) {
      throw ArgumentError('Directory does not exist: $directoryPath');
    }

    return _scanWithDart(dir, onProgress: onProgress);
  }

  /// Scans by first finding all pubspec.yaml files (fast), then checking
  /// for build directories next to them.
  Future<List<BuildDirectory>> _scanWithDart(
    Directory rootDir, {
    ScanProgressCallback? onProgress,
  }) async {
    final results = <BuildDirectory>[];
    final patterns = config.allPatterns;
    final basePath = rootDir.path;

    if (onProgress != null) {
      onProgress('Scanning for Flutter/Dart projects...');
    }

    // Step 1: Find all pubspec.yaml files using `find` (very fast)
    try {
      final result = await Process.run('find', [
        basePath,
        '-name', 'pubspec.yaml',
        '-not', '-path', '*/.git/*',
        '-not', '-path', '*/node_modules/*',
      ], stderrEncoding: const SystemEncoding());

      final pubspecPaths = (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .toList();

      // Step 2: For each pubspec.yaml, check if matching build dirs exist
      for (final pubspecPath in pubspecPaths) {
        final projectDir = p.dirname(pubspecPath);
        if (_shouldExclude(projectDir)) continue;
        if (_isInsideFlutterSdk(projectDir)) continue;

        for (final pattern in patterns) {
          final candidatePath = p.join(projectDir, pattern);
          final candidate = Directory(candidatePath);

          if (!candidate.existsSync()) continue;

          if (onProgress != null) {
            final relativePath = p.relative(candidatePath, from: basePath);
            onProgress('Calculating size: ${_shortenPath(relativePath)}');
          }

          try {
            final size = await _calculateDirectorySize(candidate);
            final record = BuildDirectory(
              path: candidatePath,
              sizeInKB: size ~/ 1024,
            );
            if (_matchesFilters(record)) {
              results.add(record);
            }
          } catch (_) {
            // Skip entries we can't measure
          }
        }
      }
    } catch (_) {
      // find command not available or failed
    }

    results.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    return results;
  }

  /// Shortens a path for display
  String _shortenPath(String path) {
    if (path.length <= 50) return path;

    final parts = path.split('/');
    if (parts.length <= 3) return path;

    // Show first part, ellipsis, and last 2 parts
    return '${parts.first}/.../${parts.sublist(parts.length - 2).join('/')}';
  }

  /// Checks if a project directory is inside a Flutter SDK installation
  bool _isInsideFlutterSdk(String projectDir) {
    var dir = projectDir;
    while (true) {
      final parent = p.dirname(dir);
      if (parent == dir) break; // reached root
      if (File(p.join(parent, 'bin', 'flutter')).existsSync()) return true;
      dir = parent;
    }
    return false;
  }

  /// Checks if a path should be excluded
  bool _shouldExclude(String path) {
    for (final pattern in config.excludePatterns) {
      if (path.contains(pattern)) return true;
    }
    return false;
  }

  /// Checks if a record matches the size filters
  bool _matchesFilters(BuildDirectory record) {
    if (config.minSizeKB != null && record.sizeInKB < config.minSizeKB!) {
      return false;
    }
    return !_shouldExclude(record.path);
  }

  /// Calculates the size of a directory in bytes
  Future<int> _calculateDirectorySize(Directory dir) async {
    int size = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
    } catch (e) {
      // Ignore permission errors
    }
    return size;
  }
}
