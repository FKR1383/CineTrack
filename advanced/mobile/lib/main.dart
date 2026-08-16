import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppConfig.validateForStartup();

  // AppLinks is created before runApp so cold-start password-reset links are
  // captured by the Flutter/Dart layer without a custom Kotlin activity.
  final appLinks = AppLinks();
  runApp(ProviderScope(child: CineTrackApp(appLinks: appLinks)));
}
