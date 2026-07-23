// ignore_for_file: depend_on_referenced_packages

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_prebuilt/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

import 'package:native_socket/src/hook/native_socket_prebuilts.g.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) {
      return;
    }

    final packageName = input.packageName;
    final sourceBuilder = CBuilder.library(
      name: packageName,
      packageName: packageName,
      assetName: 'src/$packageName.dart',
      sources: const [
        'src/native_socket.c',
      ],
    );

    await PrebuiltCodeAssetBuilder(
      assetName: 'src/$packageName.dart',
      libraryStem: 'native_socket',
      manifest: native_socketPrebuilts,
      linkModeResolver: (code) => DynamicLoadingBundled(),
      sourceFallback: SourceFallback(
        sources: [
          LocalSource(paths: const ['.']),
        ],
        builder: CallbackSourceBuilder(
          callback: ({
            required source,
            required input,
            required output,
            required logger,
          }) async {
            await sourceBuilder.run(
              input: input,
              output: output,
              logger: logger,
            );
          },
        ),
      ),
    ).run(
      input: input,
      output: output,
      logger: Logger.root
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
