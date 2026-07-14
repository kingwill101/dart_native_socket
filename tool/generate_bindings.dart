// Programmatic bindings generator using the `package:ffigen` Dart API.
//
// Usage:
//   dart run tool/generate_bindings.dart
//
// This replaces the YAML-based `ffigen:` config in pubspec.yaml.

import 'package:ffigen/ffigen.dart';

void main() {
  final ffigen = FfiGen();

  final config = Config(
    output: Uri.file('lib/src/native_socket.dart'),
    entryPoints: [Uri.file('src/native_socket.h')],
    // Only include declarations from our header, not system headers.
    shouldIncludeHeaderFunc: (Uri header) =>
        header.toFilePath().contains('native_socket.h'),
    includeUnusedTypedefs: false,
    sort: false,
    useSupportedTypedefs: true,
    ffiNativeConfig: const FfiNativeConfig(
      enabled: true,
      assetId: 'package:native_socket/src/native_socket.dart',
    ),
    compilerOpts: [
      '-I/usr/lib/clang/22/include',
      '-I/usr/local/include',
      '-I/usr/include',
    ],
    functionDecl: DeclarationFilters.includeAll,
    structDecl: DeclarationFilters.includeAll,
    unionDecl: DeclarationFilters.includeAll,
    enumClassDecl: DeclarationFilters.includeAll,
    typedefs: DeclarationFilters.includeAll,
    globals: DeclarationFilters.includeAll,
    macroDecl: DeclarationFilters.excludeAll,
    unnamedEnumConstants: DeclarationFilters.excludeAll,
  );

  ffigen.run(config);
}
