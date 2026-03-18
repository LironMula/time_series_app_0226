import 'dart:io';

Future<void> saveTextFile({
  required String suggestedName,
  String? path,
  required String contents,
}) async {
  if (path == null || path.isEmpty) {
    throw ArgumentError('A file path is required on IO platforms.');
  }
  await File(path).writeAsString(contents);
}
