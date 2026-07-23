import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:code_assets/src/code_assets/config.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:test/test.dart';

void main() {
  test('sourceFallback builds native_socket from the checked out source tree',
      () async {
    final root = Directory.current;
    final temp = await Directory.systemTemp.createTemp('native_socket_source_fallback');
    try {
      final inputBuilder = BuildInputBuilder()
        ..setupShared(
          packageRoot: root.uri,
          packageName: 'native_socket',
          outputFile: temp.uri.resolve('output.json'),
          outputDirectoryShared: temp.uri.resolve('shared/'),
        )
        ..setupBuildInput()
        ..config.setupBuild(linkingEnabled: false)
        ..config.addBuildAssetTypes(['code_assets/code'])
        ..config.setupCode(
          targetArchitecture: Architecture.x64,
          targetOS: OS.linux,
          linkModePreference: LinkModePreference.dynamic,
        );

      final input = inputBuilder.build();
      final output = BuildOutputBuilder();

      await PrebuiltCodeAssetBuilder(
        assetName: 'src/native_socket.dart',
        libraryStem: 'native_socket',
        manifest: const PrebuiltManifest(
          schemaVersion: 1,
          release: GitHubReleaseSource(
            owner: 'example',
            repository: 'example',
            tag: 'v0.0.0',
          ),
          artifacts: {},
        ),
        linkModeResolver: (_) => DynamicLoadingBundled(),
        sourceFallback: SourceFallback(
          sources: [LocalSource(paths: const ['.'])],
          builder: CallbackSourceBuilder(
            callback: ({
              required source,
              required input,
              required output,
              required logger,
            }) async {
              await CBuilder.library(
                name: 'native_socket',
                packageName: 'native_socket',
                assetName: 'src/native_socket.dart',
                sources: const ['src/native_socket.c'],
              ).run(input: input, output: output, logger: logger);
            },
          ),
        ),
      ).run(input: input, output: output, logger: Logger('native_socket_test'));

      final built = output.build();
      expect(built.assets.code, hasLength(1));
      expect(File.fromUri(built.assets.code.single.file!).existsSync(), isTrue);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
