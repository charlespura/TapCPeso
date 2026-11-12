import 'package:flutter/material.dart';
import 'screens/auth_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TapCPesoApp());
}

class TapCPesoApp extends StatelessWidget {
  const TapCPesoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TapCPeso', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF006B59)), scaffoldBackgroundColor: const Color(0xFFF5F8F7),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50)))),
    home: const AuthScreen());
}
