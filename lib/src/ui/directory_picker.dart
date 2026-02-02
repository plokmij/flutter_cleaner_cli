import 'dart:io';

import 'interactive_selector.dart';
import '../utils/format_utils.dart';

/// Entry representing a subdirectory in the picker
class _DirEntry {
  final String path;
  final String name;
  final int sizeInKB;

  _DirEntry({required this.path, required this.name, required this.sizeInKB});
}

/// Result of the directory picker
class DirectoryPickerResult {
  /// Selected directory paths to scan, or null if user quit
  final List<String>? directories;

  DirectoryPickerResult(this.directories);
}

/// Interactive picker for selecting subdirectories of a directory (e.g. home dir)
class DirectoryPicker {
  final String baseDirectory;

  DirectoryPicker({required this.baseDirectory});

  /// List non-hidden immediate subdirectories with their sizes
  Future<List<_DirEntry>> _listDirectories() async {
    final dir = Directory(baseDirectory);
    final entries = <_DirEntry>[];

    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final name = entity.path.split('/').last;
      if (name.startsWith('.')) continue;

      // Use du for fast size calculation
      int sizeKB = 0;
      try {
        final result = await Process.run('du', ['-sk', entity.path]);
        if (result.exitCode == 0) {
          final line = (result.stdout as String).trim();
          sizeKB = int.tryParse(line.split('\t').first) ?? 0;
        }
      } catch (_) {}

      entries.add(_DirEntry(path: entity.path, name: name, sizeInKB: sizeKB));
    }

    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return entries;
  }

  /// Show the interactive picker and return selected directories
  Future<DirectoryPickerResult> run() async {
    final dirs = await _listDirectories();
    if (dirs.isEmpty) {
      return DirectoryPickerResult([baseDirectory]);
    }

    // items: index 0 = "All directories", rest = actual dirs
    final selected = List.filled(dirs.length + 1, false);
    var currentIndex = 0;
    var scrollOffset = 0;
    var visibleRows = 15;

    try {
      visibleRows = stdout.terminalLines - 8;
      if (visibleRows < 5) visibleRows = 5;
      if (visibleRows > 30) visibleRows = 30;
    } catch (_) {}

    stdin.echoMode = false;
    stdin.lineMode = false;

    try {
      void render() {
        stdout.write('\x1B[2J\x1B[H');
        print(
            '${Colors.bold}${Colors.cyan}Flutter Cleaner CLI${Colors.reset}');
        print(
            '${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');
        print(
            'Home directory detected. Select directories to scan:');
        print(
            '${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');

        final totalItems = dirs.length + 1;
        final endIndex =
            (scrollOffset + visibleRows).clamp(0, totalItems);

        for (var i = scrollOffset; i < endIndex; i++) {
          final isSelected = selected[i];
          final isCurrent = i == currentIndex;

          final checkbox = isSelected
              ? '${Colors.green}[x]${Colors.reset}'
              : '${Colors.dim}[ ]${Colors.reset}';
          final highlight =
              isCurrent ? '${Colors.bgBlue}${Colors.white}' : '';
          final resetHighlight = isCurrent ? Colors.reset : '';

          if (i == 0) {
            print(
                '$highlight  $checkbox ${'All directories'.padRight(40)} ${Colors.yellow}(may take a very long time)${Colors.reset}$resetHighlight');
          } else {
            final dir = dirs[i - 1];
            final size = formatSize(dir.sizeInKB);
            print(
                '$highlight  $checkbox ${dir.name.padRight(40)} ${Colors.dim}${size.padLeft(10)}${Colors.reset}$resetHighlight');
          }
        }

        if (totalItems > visibleRows) {
          print(
              '${Colors.dim}  ... (${scrollOffset + 1}-$endIndex of $totalItems)${Colors.reset}');
        }

        print(
            '${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');
        print(
            '${Colors.dim}[Space]${Colors.reset} Toggle  '
            '${Colors.dim}[a]${Colors.reset} Select All  '
            '${Colors.dim}[n]${Colors.reset} Select None  '
            '${Colors.dim}[Enter]${Colors.reset} Confirm  '
            '${Colors.dim}[q]${Colors.reset} Quit');
      }

      render();

      while (true) {
        final key = stdin.readByteSync();

        if (key == 27) {
          final next = stdin.readByteSync();
          if (next == 91) {
            final arrow = stdin.readByteSync();
            if (arrow == 65 && currentIndex > 0) {
              currentIndex--;
              if (currentIndex < scrollOffset) scrollOffset = currentIndex;
            } else if (arrow == 66 &&
                currentIndex < dirs.length) {
              currentIndex++;
              if (currentIndex >= scrollOffset + visibleRows) {
                scrollOffset = currentIndex - visibleRows + 1;
              }
            }
          }
        } else {
          switch (key) {
            case 32: // Space
              selected[currentIndex] = !selected[currentIndex];
              // If "All" toggled on, deselect individuals; if individual toggled, deselect "All"
              if (currentIndex == 0 && selected[0]) {
                for (var i = 1; i < selected.length; i++) {
                  selected[i] = false;
                }
              } else if (currentIndex > 0 && selected[currentIndex]) {
                selected[0] = false;
              }
              break;
            case 97:
            case 65: // a/A
              selected[0] = true;
              for (var i = 1; i < selected.length; i++) {
                selected[i] = false;
              }
              break;
            case 110:
            case 78: // n/N
              for (var i = 0; i < selected.length; i++) {
                selected[i] = false;
              }
              break;
            case 10:
            case 13: // Enter
              stdout.write('\x1B[2J\x1B[H');
              if (selected[0]) {
                // "All" selected - show warning and confirm
                print(
                    '${Colors.yellow}Warning: Scanning the entire home directory may take a very long time!${Colors.reset}');
                stdout.write('Continue? [y/N] ');
                stdin.echoMode = true;
                stdin.lineMode = true;
                final answer = stdin.readLineSync()?.toLowerCase();
                if (answer != 'y' && answer != 'yes') {
                  // Go back to picker
                  stdin.echoMode = false;
                  stdin.lineMode = false;
                  selected[0] = false;
                  render();
                  continue;
                }
                return DirectoryPickerResult([baseDirectory]);
              }
              final picked = <String>[];
              for (var i = 1; i < selected.length; i++) {
                if (selected[i]) picked.add(dirs[i - 1].path);
              }
              if (picked.isEmpty) {
                // Nothing selected, re-render
                render();
                continue;
              }
              return DirectoryPickerResult(picked);
            case 113:
            case 81: // q/Q
              stdout.write('\x1B[2J\x1B[H');
              return DirectoryPickerResult(null);
          }
        }

        render();
      }
    } finally {
      stdin.echoMode = true;
      stdin.lineMode = true;
    }
  }
}
