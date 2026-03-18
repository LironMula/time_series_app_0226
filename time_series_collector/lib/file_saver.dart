import 'file_saver_stub.dart'
    if (dart.library.html) 'file_saver_web.dart'
    if (dart.library.io) 'file_saver_io.dart' as impl;

Future<void> saveTextFile({
  required String suggestedName,
  String? path,
  required String contents,
}) {
  return impl.saveTextFile(
    suggestedName: suggestedName,
    path: path,
    contents: contents,
  );
}
