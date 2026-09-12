import 'dart:convert';
import 'dart:io';

const Set<String> _historicalTextFiles = <String>{'docs/WORKLOG.md'};

void main() {
  final ProcessResult result = Process.runSync(
    'git',
    <String>['ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (result.exitCode != 0) {
    stderr.writeln('generic repository audit could not enumerate sources');
    stderr.write(result.stderr);
    exitCode = result.exitCode;
    return;
  }

  final List<String> forbidden = <String>[
    <String>['term', 'inal'].join(),
    <String>['d', 'pty'].join(),
    <String>['ターミ', 'ナル'].join(),
  ];
  final List<String> paths =
      (result.stdout as String)
          .split('\u0000')
          .where((String path) => path.isNotEmpty)
          .toList()
        ..sort();
  final List<String> violations = <String>[];
  var textFileCount = 0;

  for (final String path in paths) {
    final String normalizedPath = path.toLowerCase();
    for (final String token in forbidden) {
      if (normalizedPath.contains(token.toLowerCase())) {
        violations.add('path: $path');
        break;
      }
    }
    if (_historicalTextFiles.contains(path)) {
      continue;
    }
    final File file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final String contents;
    try {
      contents = utf8.decode(file.readAsBytesSync());
    } on FormatException {
      continue;
    }
    textFileCount++;
    final String normalizedContents = contents.toLowerCase();
    for (final String token in forbidden) {
      if (normalizedContents.contains(token.toLowerCase())) {
        violations.add('content: $path');
        break;
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('generic repository ownership violations:');
    for (final String violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'GENERIC_REPOSITORY_AUDIT_PASS '
    'paths=${paths.length} text_files=$textFileCount',
  );
}
