import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/repwise_provider.dart';
import 'screens/library_screen.dart';
import 'screens/history_screen.dart';
import 'screens/workout_screen.dart';

void main() {
  runApp(const RepwiseApp());
}

class RepwiseApp extends StatelessWidget {
  const RepwiseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RepwiseProvider()..initialize(),
      child: MaterialApp(
        title: 'Repwise',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: const Color(0xFF121212),
          snackBarTheme: const SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
        ),
        home: const RepwiseHome(),
      ),
    );
  }
}

class RepwiseHome extends StatefulWidget {
  const RepwiseHome({super.key});

  @override
  State<RepwiseHome> createState() => _RepwiseHomeState();
}

class _RepwiseHomeState extends State<RepwiseHome> {
  int _selectedIndex = 0;
  static const MethodChannel _widgetChannel = MethodChannel(
    'com.example.repwise/workout_widget',
  );

  static const List<Widget> _screens = <Widget>[
    LibraryScreen(),
    WorkoutScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _configureWidgetChannel();
  }

  Future<void> _configureWidgetChannel() async {
    _widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'startWorkoutIntent') {
        await _consumeAndHandleStartIntent();
      }
    });

    await _consumeAndHandleStartIntent();
  }

  Future<void> _consumeAndHandleStartIntent() async {
    bool shouldStart = false;
    try {
      final result = await _widgetChannel.invokeMethod<bool>(
        'consumeStartWorkoutIntent',
      );
      shouldStart = result ?? false;
    } on PlatformException {
      shouldStart = false;
    }

    if (!shouldStart || !mounted) {
      return;
    }

    await _handleStartWorkoutIntent();
  }

  Future<void> _handleStartWorkoutIntent() async {
    final provider = context.read<RepwiseProvider>();
    if (!provider.isInitialized) {
      await provider.initialize();
    }

    final bool wasActive = provider.activeSession != null;
    if (!wasActive) {
      provider.startWorkout();
    }

    if (!mounted) {
      return;
    }

    setState(() => _selectedIndex = 1);

    if (!wasActive) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Workout started.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _selectedIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) =>
            setState(() => _selectedIndex = index),
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            selectedIcon: Icon(Icons.category),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.timer_outlined),
            selectedIcon: Icon(Icons.timer),
            label: 'Workout',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'History',
          ),
        ],
      ),
    );
  }
}
