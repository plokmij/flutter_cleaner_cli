import 'dart:async';
import 'dart:convert';
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

  /// Scans using Unix find command with streaming output
  Future<List<BuildDirectory>> _scanWithFind(
    String directoryPath, {
    ScanProgressCallback? onProgress,
  }) async {
    final results = <BuildDirectory>[];

    for (final pattern in config.allPatterns) {
      // First, find all matching directories with progress reporting
      final findProcess = await Process.start(
        'find',
        ['.', '-type', 'd', '-name', pattern],
        workingDirectory: directoryPath,
      );

      final foundPaths = <String>[];

      await for (final line in findProcess.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.isNotEmpty) {
          final relativePath = line.replaceFirst('./', '');
          foundPaths.add(relativePath);

          // Report progress with shortened path
          if (onProgress != null) {
            onProgress('Found: ${_shortenPath(relativePath)}');
          }
        }
      }

      await findProcess.exitCode;

      // Now get sizes for all found directories
      if (foundPaths.isNotEmpty) {
        for (final relativePath in foundPaths) {
          final fullPath = p.join(directoryPath, relativePath);

          if (!_isFlutterProjectBuild(fullPath)) continue;

          // Report calculating size
          if (onProgress != null) {
            onProgress('Calculating size: ${_shortenPath(relativePath)}');
          }

          final duProcess = await Process.run(
            'du',
            ['-s', '-k', fullPath],
          );

          if (duProcess.exitCode == 0) {
            final output = (duProcess.stdout as String).trim();
            final record = _parseDuOutput(output, fullPath);
            if (record != null && _matchesFilters(record)) {
              results.add(record);
            }
          }
        }
      }
    }

    // Sort by size descending
    results.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    return results;
  }

  /// Scans using pure Dart (for Windows or fallback)
  Future<List<BuildDirectory>> _scanWithDart(
    Directory rootDir, {
    ScanProgressCallback? onProgress,
  }) async {
    final results = <BuildDirectory>[];
    final patternSet = config.allPatterns.toSet();
    final basePath = rootDir.path;

    try {
      await for (final entity
          in rootDir.list(recursive: true, followLinks: false)) {
        if (entity is Directory) {
          // Report current directory being scanned
          if (onProgress != null) {
            final relativePath = p.relative(entity.path, from: basePath);
            onProgress('Scanning: ${_shortenPath(relativePath)}');
          }

          final name = p.basename(entity.path);
          if (patternSet.contains(name) && !_shouldExclude(entity.path) && _isFlutterProjectBuild(entity.path)) {
            if (onProgress != null) {
              final relativePath = p.relative(entity.path, from: basePath);
              onProgress('Calculating size: ${_shortenPath(relativePath)}');
            }

            final size = await _calculateDirectorySize(entity);
            final record = BuildDirectory(
              path: entity.path,
              sizeInKB: size ~/ 1024,
            );
            if (_matchesFilters(record)) {
              results.add(record);
            }
          }
        }
      }
    } on FileSystemException {
      // Skip directories we can't access (permission denied, etc.)
    }

    results.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    return results;
  }

  /// Parses du command output
  BuildDirectory? _parseDuOutput(String output, String fullPath) {
    final pattern = RegExp(r'^(\d+)');
    final match = pattern.firstMatch(output);
    if (match != null) {
      final sizeStr = match.group(1);
      if (sizeStr != null) {
        return BuildDirectory(
          path: fullPath,
          sizeInKB: int.parse(sizeStr),
        );
      }
    }
    return null;
  }

  /// Shortens a path for display
  String _shortenPath(String path) {
    if (path.length <= 50) return path;

    final parts = path.split('/');
    if (parts.length <= 3) return path;

    // Show first part, ellipsis, and last 2 parts
    return '${parts.first}/.../${parts.sublist(parts.length - 2).join('/')}';
  }

  /// Checks if a build directory belongs to a Flutter/Dart project
  /// by looking for pubspec.yaml in its parent directory.
  bool _isFlutterProjectBuild(String buildDirPath) {
    final parent = p.dirname(buildDirPath);
    return File(p.join(parent, 'pubspec.yaml')).existsSync();
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
