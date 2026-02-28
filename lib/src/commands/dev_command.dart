import 'package:args/command_runner.dart';
import 'package:synthetic_api_cli/src/server.dart';

class DevCommand extends Command<void> {
  @override
  final name = 'dev';

  @override
  final description = 'Start the mock API server';

  DevCommand() {
    argParser.addOption(
      'config',
      abbr: 'c',
      defaultsTo: 'synthetic-api.config.json',
      help: 'Path to the config file',
    );
    argParser.addOption(
      'port',
      abbr: 'p',
      defaultsTo: '4010',
      help: 'Port to listen on',
    );
    argParser.addOption(
      'watch',
      defaultsTo: 'true',
      help: 'Watch config file for changes',
    );
  }

  @override
  Future<void> run() async {
    final configPath = argResults!['config'] as String;
    final port = int.parse(argResults!['port'] as String);
    final watch = argResults!['watch'] != 'false';
    print(
        'Starting server on port $port with config $configPath, watch=$watch');
    await startServer(configPath: configPath, port: port, watchConfig: watch);
  }
}
