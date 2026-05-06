import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/driver_login_screen.dart';
import 'screens/student_entry_screen.dart';
import 'screens/student_map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const USTEJeepApp());
}

class USTEJeepApp extends StatelessWidget {
  const USTEJeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UST E-Jeep Transit',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2196F3)),
        useMaterial3: true,
      ),
      routes: {
        '/': (context) => const RoleSelectionScreen(),
        '/driver_login': (context) => const DriverLoginScreen(),
        '/student': (context) => const StudentEntryScreen(),
        '/student_map': (context) => const StudentMapScreen(),
      },
    );
  }
}

/// Lets the user choose whether they are a driver or a student/passenger.
class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UST E-Jeep Transit'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Welcome!',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'How are you using the app today?',
                style: TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                icon: const Icon(Icons.drive_eta),
                label: const Text("I'm a Driver"),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const DriverLoginScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                icon: const Icon(Icons.directions_bus),
                label: const Text("I'm a Student"),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StudentEntryScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
