import 'package:flutter_cleaner_cli/flutter_cleaner_cli.dart';
import 'package:test/test.dart';

void main() {
  group('BuildDirectory', () {
    test('formattedSize returns KB for small sizes', () {
      final dir = BuildDirectory(path: '/test/build', sizeInKB: 500);
      expect(dir.formattedSize, '500 KB');
    });

    test('formattedSize returns MB for medium sizes', () {
      final dir = BuildDirectory(path: '/test/build', sizeInKB: 1024);
      expect(dir.formattedSize, '1.0 MB');
    });

    test('formattedSize returns GB for large sizes', () {
      final dir = BuildDirectory(path: '/test/build', sizeInKB: 1024 * 1024 * 2);
      expect(dir.formattedSize, '2.0 GB');
    });

    test('copyWith creates new instance with updated values', () {
      final dir = BuildDirectory(path: '/test/build', sizeInKB: 1024);
      final updated = dir.copyWith(isSelected: true);
      expect(updated.isSelected, true);
      expect(updated.path, dir.path);
      expect(updated.sizeInKB, dir.sizeInKB);
    });
  });

  group('formatSize', () {
    test('formats KB correctly', () {
      expect(formatSize(500), '500 KB');
    });

    test('formats MB correctly', () {
      expect(formatSize(1024), '1.0 MB');
    });

    test('formats GB correctly', () {
      expect(formatSize(1024 * 1024), '1.0 GB');
    });
  });

  group('ScanConfig', () {
    test('allPatterns includes build by default', () {
      const config = ScanConfig();
      expect(config.allPatterns, contains('build'));
    });

    test('allPatterns includes .dart_tool when enabled', () {
      const config = ScanConfig(includeDartTool: true);
      expect(config.allPatterns, contains('.dart_tool'));
    });
  });
}
