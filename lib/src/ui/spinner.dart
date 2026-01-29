import 'dart:async';
import 'dart:io';

/// Animated spinner for loading indication
class Spinner {
  Spinner({
    this.message = 'Loading',
    this.frames = const ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏'],
    this.interval = const Duration(milliseconds: 80),
  });

  String message;
  final List<String> frames;
  final Duration interval;

  Timer? _timer;
  int _frameIndex = 0;
  bool _isRunning = false;

  /// Starts the spinner animation
  void start() {
    if (_isRunning) return;
    _isRunning = true;
    _frameIndex = 0;

    // Hide cursor
    stdout.write('\x1B[?25l');

    _timer = Timer.periodic(interval, (_) {
      _render();
      _frameIndex = (_frameIndex + 1) % frames.length;
    });

    _render();
  }

  /// Updates the spinner message
  void update(String newMessage) {
    message = newMessage;
  }

  /// Stops the spinner with a success message
  void success(String successMessage) {
    _stop();
    stdout.write('\r\x1B[32m✓\x1B[0m $successMessage\n');
  }

  /// Stops the spinner with an error message
  void error(String errorMessage) {
    _stop();
    stdout.write('\r\x1B[31m✗\x1B[0m $errorMessage\n');
  }

  /// Stops the spinner with an info message
  void info(String infoMessage) {
    _stop();
    stdout.write('\r\x1B[34mℹ\x1B[0m $infoMessage\n');
  }

  /// Stops the spinner without a final message
  void stop() {
    _stop();
    _clearLine();
    stdout.write('\r');
  }

  void _render() {
    _clearLine();
    stdout.write('\r\x1B[36m${frames[_frameIndex]}\x1B[0m $message');
  }

  void _clearLine() {
    stdout.write('\r\x1B[K');
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    // Show cursor
    stdout.write('\x1B[?25h');
  }
}

/// Runs an async operation with a spinner
Future<T> withSpinner<T>({
  required Future<T> Function() operation,
  required String message,
  String? successMessage,
  String? errorMessage,
}) async {
  final spinner = Spinner(message: message);
  spinner.start();

  try {
    final result = await operation();
    if (successMessage != null) {
      spinner.success(successMessage);
    } else {
      spinner.stop();
    }
    return result;
  } catch (e) {
    spinner.error(errorMessage ?? 'Error: $e');
    rethrow;
  }
}
