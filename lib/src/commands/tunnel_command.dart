import 'package:args/command_runner.dart';
import 'package:synthetic_api_cli/src/tunnel.dart';

class TunnelCommand extends Command<void> {
  @override
  final name = 'tunnel';

  @override
  final description = 'Start the tunnel';

  TunnelCommand() {
    argParser.addOption(
      'port',
      abbr: 'p',
      defaultsTo: '4010',
      help: 'Port to listen on',
    );
    argParser.addOption(
      'provider',
      abbr: 'r',
      defaultsTo: 'auto',
      help: 'Provider to use for the tunnel',
    );
  }

  @override
  Future<void> run() async {
    final port = int.parse(argResults!['port'] as String);
    final provider = argResults!['provider'] as String;
    await startTunnel(port: port, provider: provider);
  }
}
