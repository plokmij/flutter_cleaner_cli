import 'dart:io';

import '../models/build_directory.dart';
import '../utils/format_utils.dart';

/// ANSI color codes
class Colors {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const blue = '\x1B[34m';
  static const magenta = '\x1B[35m';
  static const cyan = '\x1B[36m';
  static const white = '\x1B[37m';
  static const bgBlue = '\x1B[44m';
}

/// Result of interactive selection
class SelectionResult {
  const SelectionResult({
    required this.selected,
    required this.action,
  });

  final List<BuildDirectory> selected;
  final SelectionAction action;
}

enum SelectionAction {
  delete,
  quit,
}

/// Interactive directory selector TUI
class InteractiveSelector {
  InteractiveSelector({
    required this.directories,
    this.baseDirectory = '',
  }) : _selected = List.filled(directories.length, false);

  final List<BuildDirectory> directories;
  final String baseDirectory;
  final List<bool> _selected;

  int _currentIndex = 0;
  int _scrollOffset = 0;
  int _visibleRows = 15;

  /// Runs the interactive selection UI
  Future<SelectionResult> run() async {
    if (directories.isEmpty) {
      print('${Colors.yellow}No build directories found.${Colors.reset}');
      return SelectionResult(selected: [], action: SelectionAction.quit);
    }

    // Enable raw mode for single key input
    stdin.echoMode = false;
    stdin.lineMode = false;

    try {
      _calculateVisibleRows();
      _render();

      while (true) {
        final key = stdin.readByteSync();

        // Handle arrow keys (escape sequences)
        if (key == 27) {
          // ESC
          final next = stdin.readByteSync();
          if (next == 91) {
            // [
            final arrow = stdin.readByteSync();
            switch (arrow) {
              case 65: // Up
                _moveUp();
                break;
              case 66: // Down
                _moveDown();
                break;
            }
          }
        } else {
          switch (key) {
            case 32: // Space - toggle selection
              _toggleCurrent();
              break;
            case 97: // 'a' - select all
            case 65: // 'A'
              _selectAll();
              break;
            case 110: // 'n' - select none
            case 78: // 'N'
              _selectNone();
              break;
            case 100: // 'd' - delete
            case 68: // 'D'
            case 13: // Enter
              final selected = _getSelectedDirectories();
              if (selected.isNotEmpty) {
                _clearScreen();
                return SelectionResult(
                  selected: selected,
                  action: SelectionAction.delete,
                );
              }
              break;
            case 113: // 'q' - quit
            case 81: // 'Q'
            case 27: // ESC (handled above for arrow keys, but also quit)
              _clearScreen();
              return SelectionResult(
                selected: [],
                action: SelectionAction.quit,
              );
          }
        }

        _render();
      }
    } finally {
      // Restore terminal mode
      stdin.echoMode = true;
      stdin.lineMode = true;
    }
  }

  void _calculateVisibleRows() {
    // Try to get terminal size, default to 15 visible rows
    try {
      _visibleRows = stdout.terminalLines - 10;
      if (_visibleRows < 5) _visibleRows = 5;
      if (_visibleRows > 30) _visibleRows = 30;
    } catch (_) {
      _visibleRows = 15;
    }
  }

  void _moveUp() {
    if (_currentIndex > 0) {
      _currentIndex--;
      if (_currentIndex < _scrollOffset) {
        _scrollOffset = _currentIndex;
      }
    }
  }

  void _moveDown() {
    if (_currentIndex < directories.length - 1) {
      _currentIndex++;
      if (_currentIndex >= _scrollOffset + _visibleRows) {
        _scrollOffset = _currentIndex - _visibleRows + 1;
      }
    }
  }

  void _toggleCurrent() {
    _selected[_currentIndex] = !_selected[_currentIndex];
  }

  void _selectAll() {
    for (var i = 0; i < _selected.length; i++) {
      _selected[i] = true;
    }
  }

  void _selectNone() {
    for (var i = 0; i < _selected.length; i++) {
      _selected[i] = false;
    }
  }

  List<BuildDirectory> _getSelectedDirectories() {
    final result = <BuildDirectory>[];
    for (var i = 0; i < directories.length; i++) {
      if (_selected[i]) {
        result.add(directories[i]);
      }
    }
    return result;
  }

  int _getSelectedCount() => _selected.where((s) => s).length;

  int _getSelectedSize() {
    int total = 0;
    for (var i = 0; i < directories.length; i++) {
      if (_selected[i]) {
        total += directories[i].sizeInKB;
      }
    }
    return total;
  }

  int _getTotalSize() {
    return directories.fold(0, (sum, dir) => sum + dir.sizeInKB);
  }

  void _clearScreen() {
    stdout.write('\x1B[2J\x1B[H');
  }

  void _render() {
    _clearScreen();

    // Header
    print('${Colors.bold}${Colors.cyan}Flutter Cleaner CLI${Colors.reset}');
    print('${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');
    if (baseDirectory.isNotEmpty) {
      print('${Colors.dim}Scanning: $baseDirectory${Colors.reset}');
    }
    print(
        'Found: ${Colors.bold}${directories.length}${Colors.reset} build directories | '
        'Total: ${Colors.bold}${formatSize(_getTotalSize())}${Colors.reset}');
    print('${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');

    // Directory list
    final endIndex = (_scrollOffset + _visibleRows).clamp(0, directories.length);
    for (var i = _scrollOffset; i < endIndex; i++) {
      final dir = directories[i];
      final isSelected = _selected[i];
      final isCurrent = i == _currentIndex;

      final checkbox = isSelected
          ? '${Colors.green}[x]${Colors.reset}'
          : '${Colors.dim}[ ]${Colors.reset}';

      final highlight = isCurrent ? '${Colors.bgBlue}${Colors.white}' : '';
      final resetHighlight = isCurrent ? Colors.reset : '';

      // Shorten the path for display
      var displayPath = dir.path;
      if (baseDirectory.isNotEmpty && displayPath.startsWith(baseDirectory)) {
        displayPath = displayPath.substring(baseDirectory.length);
        if (displayPath.startsWith('/')) {
          displayPath = displayPath.substring(1);
        }
      }
      displayPath = truncatePath(displayPath, maxLength: 50);

      // Color code by size
      String sizeColor;
      if (dir.sizeInKB >= 500 * 1024) {
        // >= 500MB
        sizeColor = Colors.red;
      } else if (dir.sizeInKB >= 100 * 1024) {
        // >= 100MB
        sizeColor = Colors.yellow;
      } else {
        sizeColor = Colors.dim;
      }

      print(
          '$highlight  $checkbox ${displayPath.padRight(52)} $sizeColor${dir.formattedSize.padLeft(10)}${Colors.reset}$resetHighlight');
    }

    // Show scroll indicator if needed
    if (directories.length > _visibleRows) {
      print(
          '${Colors.dim}  ... (${_scrollOffset + 1}-$endIndex of ${directories.length})${Colors.reset}');
    }

    // Footer
    print('${Colors.dim}─────────────────────────────────────────────────────────────${Colors.reset}');
    final selectedCount = _getSelectedCount();
    final selectedSize = _getSelectedSize();
    print(
        'Selected: ${Colors.bold}$selectedCount${Colors.reset} directories '
        '(${Colors.bold}${formatSize(selectedSize)}${Colors.reset})');
    print('');
    print(
        '${Colors.dim}[Space]${Colors.reset} Toggle  '
        '${Colors.dim}[a]${Colors.reset} Select All  '
        '${Colors.dim}[n]${Colors.reset} Select None  '
        '${Colors.dim}[d/Enter]${Colors.reset} Delete  '
        '${Colors.dim}[q]${Colors.reset} Quit');
  }
}
