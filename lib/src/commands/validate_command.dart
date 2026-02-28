import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:synthetic_api_cli/src/config.dart';
import 'package:synthetic_api_cli/src/validate.dart';

class ValidateCommand extends Command<void> {
  @override
  final name = 'validate';

  @override
  final description = 'Validate a synthetic-api config file';

  ValidateCommand() {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'synthetic-api.config.json',
      help: 'Path to the config file',
    );
  }

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;

    final loaded = await loadConfig(configPath);
    final errors = validateConfig(loaded.config);

    if (errors.isEmpty) {
      print('Config valid: ${loaded.configPath}');
      return;
    }

    print('Config invalid:\n');
    for (final error in errors) {
      print('  - $error');
    }
    exitCode = 1;
  }
}
