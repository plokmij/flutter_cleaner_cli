import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/build_directory.dart';
import '../utils/platform_utils.dart';

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
  Future<List<BuildDirectory>> scan(String directoryPath) async {
    final expandedPath = expandPath(directoryPath);
    final dir = Directory(expandedPath);

    if (!await dir.exists()) {
      throw ArgumentError('Directory does not exist: $directoryPath');
    }

    final platform = getCurrentPlatform();

    if (platform == SupportedPlatform.macOS ||
        platform == SupportedPlatform.linux) {
      return _scanWithFind(expandedPath);
    } else {
      return _scanWithDart(dir);
    }
  }

  /// Scans using Unix find command (faster on macOS/Linux)
  Future<List<BuildDirectory>> _scanWithFind(String directoryPath) async {
    final results = <BuildDirectory>[];

    for (final pattern in config.allPatterns) {
      final process = await Process.run(
        'find',
        [
          '.',
          '-type',
          'd',
          '-name',
          pattern,
          '-exec',
          'du',
          '-s',
          '-k',
          '{}',
          '+',
        ],
        workingDirectory: directoryPath,
      );

      if (process.exitCode == 0) {
        final lines = (process.stdout as String).split('\n');
        for (final line in lines) {
          final record = _parseDiskUsageLine(line, directoryPath);
          if (record != null && _matchesFilters(record)) {
            results.add(record);
          }
        }
      }
    }

    // Sort by size descending
    results.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    return results;
  }

  /// Scans using pure Dart (for Windows or fallback)
  Future<List<BuildDirectory>> _scanWithDart(Directory rootDir) async {
    final results = <BuildDirectory>[];
    final patternSet = config.allPatterns.toSet();

    await for (final entity in rootDir.list(recursive: true, followLinks: false)) {
      if (entity is Directory) {
        final name = p.basename(entity.path);
        if (patternSet.contains(name) && !_shouldExclude(entity.path)) {
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

    results.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    return results;
  }

  /// Parses a line from du output
  BuildDirectory? _parseDiskUsageLine(String line, String basePath) {
    final pattern = RegExp(r'([0-9]+)\s+(.+)$');
    final match = pattern.firstMatch(line);
    if (match != null) {
      final sizeStr = match.group(1);
      final pathStr = match.group(2);
      if (sizeStr != null && pathStr != null) {
        // Convert relative path to absolute
        final relativePath = pathStr.trim().replaceFirst('./', '');
        final fullPath = p.join(basePath, relativePath);
        return BuildDirectory(
          path: fullPath,
          sizeInKB: int.parse(sizeStr),
        );
      }
    }
    return null;
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
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
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
