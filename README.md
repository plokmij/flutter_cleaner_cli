# Flutter Cleaner CLI

A cross-platform command-line tool to clean Flutter build directories and free up disk space.

> **Note:** This is a vibecoded project - built collaboratively with AI assistance.

## Features

- **Interactive TUI** - Navigate with arrow keys, select with checkboxes
- **Cross-platform** - Works on macOS, Linux, and Windows
- **Safe deletion** - Moves to trash by default (recoverable)
- **Dry-run mode** - Preview what would be deleted
- **Size filters** - Only show directories above a threshold
- **Custom patterns** - Search for custom folder names
- **JSON output** - Machine-readable output for scripting

## Installation

### From source

```bash
# Clone the repository
git clone https://github.com/user/flutter_cleaner_cli.git
cd flutter_cleaner_cli

# Install dependencies
dart pub get

# Run directly
dart run bin/flutter_cleaner.dart

# Or compile to native binary
dart compile exe bin/flutter_cleaner.dart -o flutter_cleaner
```

## Usage

```bash
# Interactive mode in current directory
flutter_cleaner

# Scan specific directory
flutter_cleaner ~/projects

# Preview what would be deleted (dry-run)
flutter_cleaner --dry-run ~/projects

# Also clean .dart_tool directories
flutter_cleaner --dart-tool ~/projects

# Non-interactive mode (auto-confirm)
flutter_cleaner -y ~/projects

# Only show directories >= 100MB
flutter_cleaner --min-size 100MB ~/projects

# JSON output for scripting
flutter_cleaner -o json ~/projects

# Custom patterns
flutter_cleaner --pattern "build,.dart_tool,node_modules" ~/projects

# Exclude patterns
flutter_cleaner --exclude "important_project" ~/projects

# Permanent delete (not recoverable)
flutter_cleaner --permanent ~/projects
```

## Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-v, --version` | Show version |
| `-y, --yes` | Auto-confirm deletion (non-interactive) |
| `--dry-run` | Preview what would be deleted |
| `--permanent` | Permanently delete instead of moving to trash |
| `--dart-tool` | Also clean .dart_tool directories |
| `--min-size` | Minimum size to include (e.g., 50MB, 1GB) |
| `--pattern` | Custom folder patterns (comma-separated) |
| `--exclude` | Patterns to exclude (comma-separated) |
| `-o, --output` | Output format: text, json |

## Interactive Controls

| Key | Action |
|-----|--------|
| `↑/↓` | Navigate list |
| `Space` | Toggle selection |
| `a` | Select all |
| `n` | Select none |
| `d` / `Enter` | Delete selected |
| `q` | Quit |

## Development

```bash
# Run tests
dart test

# Run analyzer
dart analyze

# Format code
dart format .
```

## License

MIT
