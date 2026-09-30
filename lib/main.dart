import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/equipment_repository.dart';
import 'screens/auth_gate.dart';
import 'screens/marketplace_screen.dart';
import 'theme.dart';

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseClient? client;

  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
      client = Supabase.instance.client;
    } catch (error) {
      debugPrint('FlexShare could not initialize Supabase: $error');
    }
  }

  runApp(FlexShareApp(client: client));
}

class FlexShareApp extends StatelessWidget {
  const FlexShareApp({super.key, required this.client});

  final SupabaseClient? client;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlexShare | PSU',
      debugShowCheckedModeBanner: false,
      theme: FlexShareTheme.light,
      home: client == null
          ? MarketplaceScreen(
              repository: EquipmentRepository(null),
              profile: null,
              demoMode: true,
            )
          : AuthGate(client: client!),
    );
  }
}