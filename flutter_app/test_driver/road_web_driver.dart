import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final directory = Directory('build/reports/roads-web');
  await directory.create(recursive: true);
  await integrationDriver(onScreenshot: (String name, List<int> bytes,
      [Map<String, Object?>? args]) async {
    await File('${directory.path}/$name.png').writeAsBytes(bytes);
    return true;
  });
}
