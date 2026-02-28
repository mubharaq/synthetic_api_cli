import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:synthetic_api_cli/src/init.dart';

class InitCommand extends Command<void> {
  @override
  final name = 'init';

  @override
  final description = 'Initialize a new synthetic-api project';

  InitCommand() {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'synthetic-api.config.json',
      help: 'Path to the config file',
    );
    argParser.addFlag(
      'force',
      abbr: 'f',
      defaultsTo: false,
      help: 'Force re-initialization',
    );
  }

  @override
  Future<void> run() async {
    final configFile = argResults!['config'] as String;
    final force = argResults!['force'] as bool;
    final result = await initializeProject(
      cwd: Directory.current.path,
      configFile: configFile,
      force: force,
    );

    for (final f in result.filesCreated) {
      print('Created: $f');
    }
    for (final f in result.filesUpdated) {
      print('Updated: $f');
    }
    for (final f in result.filesSkipped) {
      print('Skipped: $f');
    }
  }
}
