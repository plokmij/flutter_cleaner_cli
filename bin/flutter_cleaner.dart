import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_cleaner_cli/src/core/scanner.dart';
import 'package:flutter_cleaner_cli/src/core/cleaner.dart';
import 'package:flutter_cleaner_cli/src/models/build_directory.dart';
import 'package:flutter_cleaner_cli/src/ui/directory_picker.dart';
import 'package:flutter_cleaner_cli/src/ui/interactive_selector.dart';
import 'package:flutter_cleaner_cli/src/ui/spinner.dart';
import 'package:flutter_cleaner_cli/src/utils/format_utils.dart';
import 'package:flutter_cleaner_cli/src/utils/platform_utils.dart';

const version = '1.1.2';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help message')
    ..addFlag('version', abbr: 'v', negatable: false, help: 'Show version')
    ..addFlag('yes', abbr: 'y', negatable: false, help: 'Auto-confirm deletion (non-interactive)')
    ..addFlag('dry-run', negatable: false, help: 'Preview what would be deleted')
    ..addFlag('permanent', negatable: false, help: 'Permanently delete instead of moving to trash')
    ..addFlag('dart-tool', negatable: false, help: 'Also clean .dart_tool directories')
    ..addOption('min-size', help: 'Minimum size to include (e.g., 50MB, 1GB)')
    ..addOption('pattern', help: 'Custom folder patterns (comma-separated)', defaultsTo: 'build')
    ..addOption('exclude', help: 'Patterns to exclude (comma-separated)')
    ..addOption('output', abbr: 'o', help: 'Output format: text, json', defaultsTo: 'text');

  ArgResults results;
  try {
    results = parser.parse(arguments);
  } catch (e) {
    print('Error: $e');
    print('');
    _printUsage(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    _printUsage(parser);
    exit(0);
  }

  if (results['version'] as bool) {
    print('Flutter Cleaner CLI v$version');
    exit(0);
  }

  // Determine directory to scan
  String targetDir;
  if (results.rest.isNotEmpty) {
    targetDir = results.rest.first;
  } else {
    targetDir = Directory.current.path;
  }

  // Expand and validate path
  targetDir = expandPath(targetDir);
  targetDir = p.canonicalize(targetDir);

  if (!Directory(targetDir).existsSync()) {
    print('Error: Directory does not exist: $targetDir');
    exit(1);
  }

  // Parse options
  final dryRun = results['dry-run'] as bool;
  final autoConfirm = results['yes'] as bool;
  final permanent = results['permanent'] as bool;
  final includeDartTool = results['dart-tool'] as bool;
  final outputFormat = results['output'] as String;

  // Parse min-size
  int? minSizeKB;
  final minSizeStr = results['min-size'] as String?;
  if (minSizeStr != null) {
    minSizeKB = _parseSize(minSizeStr);
    if (minSizeKB == null) {
      print('Error: Invalid size format: $minSizeStr');
      print('Use formats like: 50MB, 1GB, 500KB');
      exit(1);
    }
  }

  // Parse patterns
  final patternStr = results['pattern'] as String;
  final patterns = patternStr.split(',').map((s) => s.trim()).toList();

  // Parse exclude patterns
  List<String> excludePatterns = [];
  final excludeStr = results['exclude'] as String?;
  if (excludeStr != null) {
    excludePatterns = excludeStr.split(',').map((s) => s.trim()).toList();
  }

  // Home directory guard: show directory picker instead of scanning everything
  List<String> scanTargets = [targetDir];
  if (isHomeDirectory(targetDir)) {
    if (autoConfirm) {
      print('\x1B[33mWarning: Scanning the entire home directory may take a very long time!\x1B[0m');
    } else {
      final picker = DirectoryPicker(baseDirectory: targetDir);
      final pickerResult = await picker.run();
      if (pickerResult.directories == null) {
        print('Cancelled.');
        exit(0);
      }
      scanTargets = pickerResult.directories!;
    }
  }

  // Create scanner config
  final config = ScanConfig(
    patterns: patterns,
    excludePatterns: excludePatterns,
    minSizeKB: minSizeKB,
    includeDartTool: includeDartTool,
  );

  // Run the scan with spinner
  final scanner = Scanner(config: config);
  final stopwatch = Stopwatch()..start();
  final scanSpinner = Spinner(message: 'Scanning...');
  scanSpinner.start();

  List<BuildDirectory> directories;
  try {
    final allResults = <BuildDirectory>[];
    for (final target in scanTargets) {
      final results = await scanner.scan(
        target,
        onProgress: (currentPath) {
          scanSpinner.update(currentPath);
        },
      );
      allResults.addAll(results);
    }
    allResults.sort((a, b) => b.sizeInKB.compareTo(a.sizeInKB));
    directories = allResults;
  } catch (e) {
    scanSpinner.error('Error scanning: $e');
    exit(1);
  }

  stopwatch.stop();

  if (directories.isEmpty) {
    scanSpinner.info('No build directories found.');
    exit(0);
  }

  scanSpinner.success(
    'Found ${directories.length} build directories in ${formatDuration(stopwatch.elapsed)}',
  );
  print('');

  // Calculate totals
  final totalSize = directories.fold(0, (int sum, dir) => sum + dir.sizeInKB);
  print('Total size: ${formatSize(totalSize)}');
  print('');

  // Output mode: JSON
  if (outputFormat == 'json') {
    _outputJson(directories, targetDir);
    exit(0);
  }

  // Dry run mode
  if (dryRun) {
    print('Dry run - would delete:');
    print('');
    for (final dir in directories) {
      print('  ${dir.formattedSize.padLeft(10)}  ${dir.path}');
    }
    print('');
    print('Total: ${formatSize(totalSize)}');
    exit(0);
  }

  // Non-interactive mode with auto-confirm
  if (autoConfirm) {
    await _deleteDirectories(directories, permanent: permanent, autoConfirm: true);
    exit(0);
  }

  // Interactive mode
  final selector = InteractiveSelector(
    directories: directories,
    baseDirectory: targetDir,
  );

  final selectionResult = await selector.run();

  if (selectionResult.action == SelectionAction.quit ||
      selectionResult.selected.isEmpty) {
    print('No directories selected. Exiting.');
    exit(0);
  }

  // Confirm deletion
  final selectedSize = selectionResult.selected.fold<int>(0, (sum, dir) => sum + dir.sizeInKB);
  final projectNames = selectionResult.selected
      .map((dir) => p.basename(p.dirname(dir.path)))
      .toSet()
      .toList()
    ..sort();
  print('');
  print('About to ${permanent ? "permanently delete" : "move to trash"} ${selectionResult.selected.length} directories (${formatSize(selectedSize)})');
  print('Projects: ${projectNames.join(', ')}');
  stdout.write('Continue? [y/N] ');

  final confirmation = stdin.readLineSync()?.toLowerCase();
  if (confirmation != 'y' && confirmation != 'yes') {
    print('Cancelled.');
    exit(0);
  }

  await _deleteDirectories(selectionResult.selected, permanent: permanent, autoConfirm: false);
}

void _printUsage(ArgParser parser) {
  print('Flutter Cleaner CLI v$version');
  print('');
  print('A tool to clean Flutter build directories and free up disk space.');
  print('');
  print('Usage: flutter_cleaner [options] [directory]');
  print('');
  print('Options:');
  print(parser.usage);
  print('');
  print('Examples:');
  print('  flutter_cleaner                    # Interactive mode in current directory');
  print('  flutter_cleaner ~/projects         # Scan specific directory');
  print('  flutter_cleaner --dry-run          # Preview what would be deleted');
  print('  flutter_cleaner -y --min-size 100MB  # Auto-delete dirs >= 100MB');
  print('  flutter_cleaner --dart-tool        # Also clean .dart_tool directories');
}

int? _parseSize(String sizeStr) {
  final pattern = RegExp(r'^(\d+(?:\.\d+)?)\s*(KB|MB|GB)?$', caseSensitive: false);
  final match = pattern.firstMatch(sizeStr.toUpperCase());
  if (match == null) return null;

  final value = double.parse(match.group(1)!);
  final unit = match.group(2) ?? 'KB';

  switch (unit) {
    case 'KB':
      return value.toInt();
    case 'MB':
      return (value * 1024).toInt();
    case 'GB':
      return (value * 1024 * 1024).toInt();
    default:
      return value.toInt();
  }
}

void _outputJson(List<BuildDirectory> directories, String baseDir) {
  print('[');
  for (var i = 0; i < directories.length; i++) {
    final dir = directories[i];
    final comma = i < directories.length - 1 ? ',' : '';
    print('  {"path": "${dir.path}", "sizeKB": ${dir.sizeInKB}, "sizeFormatted": "${dir.formattedSize}"}$comma');
  }
  print(']');
}

Future<void> _deleteDirectories(List<BuildDirectory> directories, {bool permanent = false, bool autoConfirm = false}) async {
  final cleaner = createCleaner();

  print('');
  final deleteSpinner = Spinner(
    message: permanent ? 'Permanently deleting...' : 'Moving to trash...',
  );
  deleteSpinner.start();

  final result = await cleaner.cleanDirectories(directories, permanent: permanent);

  if (result.failCount == 0) {
    deleteSpinner.success(
      '${permanent ? "Deleted" : "Moved to trash"}: ${result.successCount} directories (${formatSize(result.totalSize)})',
    );
  } else if (result.successCount > 0) {
    deleteSpinner.info(
      '${permanent ? "Deleted" : "Moved"}: ${result.successCount} directories (${formatSize(result.totalSize)})',
    );
    print('\x1B[33m!\x1B[0m Failed: ${result.failCount} directories');
    for (final dir in result.failed) {
      print('  - ${dir.path}');
    }
  } else {
    deleteSpinner.error('Failed to delete ${result.failCount} directories');
    for (final dir in result.failed) {
      print('  - ${dir.path}');
    }
  }

  // Offer to permanently remove trashed items
  if (!permanent && result.successCount > 0 && !autoConfirm) {
    print('');
    stdout.write('Permanently remove these from trash? [y/N] ');
    final answer = stdin.readLineSync()?.toLowerCase();
    if (answer == 'y' || answer == 'yes') {
      // Try removing individual items first
      int removed = 0;
      for (final dir in result.successful) {
        if (await cleaner.deleteFromTrash(dir.path)) {
          removed++;
        }
      }
      if (removed > 0) {
        print('Permanently removed $removed item${removed == 1 ? '' : 's'} from trash.');
      } else {
        // Individual deletion failed (likely macOS TCC restriction),
        // fall back to emptying trash via Finder
        stdout.write('Could not remove individual items. Empty entire trash instead? [y/N] ');
        final emptyAnswer = stdin.readLineSync()?.toLowerCase();
        if (emptyAnswer == 'y' || emptyAnswer == 'yes') {
          if (await cleaner.emptyTrash()) {
            print('Trash emptied.');
          } else {
            print('Failed to empty trash. You may need to empty it manually from Finder.');
          }
        }
      }
    }
  }
}
