/// Aplicação Flutter LogiPredictAI — previsão de atraso em entregas logísticas.
///
/// Ponto de entrada da aplicação com suporte a tema claro/escuro.
/// A tela inicial é o [DashboardScreen] com abas para simulação, mapa,
/// análise e importação de dados Olist.
library;

import 'package:flutter/material.dart';
import 'screens/dashboard_screen.dart';

/// Inicia a aplicação Flutter.
void main() => runApp(const LogiPredictApp());

const navy = Color(0xFF0F172A);
const blue = Color(0xFF2563EB);
const pageBg = Color(0xFFF8FAFC);

class LogiPredictApp extends StatefulWidget {
  const LogiPredictApp({super.key});

  @override
  State<LogiPredictApp> createState() => _LogiPredictAppState();
}

class _LogiPredictAppState extends State<LogiPredictApp> {
  ThemeMode _themeMode = ThemeMode.light;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LogiPredict AI',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: pageBg,
        appBarTheme: const AppBarTheme(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blue,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        canvasColor: const Color(0xFF0B1120),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF111827),
          foregroundColor: Colors.white,
          elevation: 1,
        ),
        cardColor: const Color(0xFF1E293B),
        dividerColor: const Color(0xFF334155),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E293B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF475569)),
          ),
        ),
      ),
      home: DashboardScreen(
        isDarkMode: _themeMode == ThemeMode.dark,
        onThemeToggle: _toggleTheme,
      ),
    );
  }
}
