import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'views/screens/landing_screen.dart';
import 'views/screens/register_screen.dart';
import 'views/screens/home_feed.dart';
import 'views/screens/login_screen.dart';
import 'views/screens/admin_home_screen.dart';
import 'services/firebase_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PawWatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B2A4A)),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
      routes: {
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const HomeScreen(),
        '/login': (context) => const LoginScreen(),
        '/admin': (context) => const AdminHomeScreen(),
      },
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAF9F7),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF9B8EC4),
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        if (snapshot.hasData && snapshot.data != null) {
          final user = snapshot.data!;
          // Route admin to admin panel
          if (user.email == 'admin@example.com') {
            return const AdminHomeScreen();
          }
          // Route regular user through ban verification gate
          return _UserGate(user: user);
        }
        return const LandingScreen();
      },
    );
  }
}

class _UserGate extends StatelessWidget {
  final User user;
  const _UserGate({required this.user});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: FirebaseService.instance.isUserBanned(user.uid, email: user.email),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAF9F7),
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFF9B8EC4),
                strokeWidth: 2.5,
              ),
            ),
          );
        }
        if (snapshot.data == true) {
          return _BannedUserScreen(user: user);
        }
        // Ensure Firestore user doc exists for active valid user
        FirebaseService.instance.ensureUserDoc(user);
        return const HomeScreen();
      },
    );
  }
}

class _BannedUserScreen extends StatelessWidget {
  final User user;
  const _BannedUserScreen({required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F7),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.block_rounded,
                    size: 64,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account Banned',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1B2A4A),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account (${user.email ?? "User"}) has been banned by an administrator for violating PawWatch community guidelines. Access to the app has been revoked.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B2A4A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text(
                      'Log Out',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}