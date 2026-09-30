import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/equipment_repository.dart';
import 'marketplace_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.client});

  final SupabaseClient client;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final EquipmentRepository _repository;
  StreamSubscription<AuthState>? _authSubscription;
  Future<Map<String, dynamic>?>? _profileFuture;

  @override
  void initState() {
    super.initState();
    _repository = EquipmentRepository(widget.client);
    _authSubscription = widget.client.auth.onAuthStateChange.listen((_) {
      if (!mounted) return;
      setState(() => _profileFuture = null);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.client.auth.currentUser == null) {
      return _SignInScreen(
        client: widget.client,
        onAuthenticated: () => setState(() => _profileFuture = null),
      );
    }

    _profileFuture ??= _repository.currentProfile();
    return FutureBuilder<Map<String, dynamic>?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return _ProfileSetupError(
            client: widget.client,
            message: snapshot.hasError
                ? 'We could not load your PSU profile. Check your connection and try again.'
                : 'Your account needs a PSU student profile before you can continue.',
            onRetry: () => setState(() => _profileFuture = null),
          );
        }
        return MarketplaceScreen(
          repository: _repository,
          profile: snapshot.data,
          demoMode: false,
        );
      },
    );
  }
}

class _SignInScreen extends StatefulWidget {
  const _SignInScreen({required this.client, required this.onAuthenticated});

  final SupabaseClient client;
  final VoidCallback onAuthenticated;

  @override
  State<_SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<_SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String _department = 'IT';
  bool _creatingAccount = false;
  bool _submitting = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _studentIdController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _message = null;
      _error = null;
    });

    try {
      if (_creatingAccount) {
        final response = await widget.client.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'full_name': _nameController.text.trim(),
            'student_id_number': _studentIdController.text.trim(),
            'department': _department,
          },
        );
        if (response.session == null) {
          setState(() => _message =
              'Check your student email to confirm your account, then sign in.');
        } else {
          widget.onAuthenticated();
        }
      } else {
        await widget.client.auth.signInWithPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        widget.onAuthenticated();
      }
    } on AuthException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not reach FlexShare. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 680;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(isWide ? 32 : 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'FlexShare',
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _creatingAccount
                            ? 'Join your PSU campus marketplace.'
                            : 'Sign in to see what’s available between classes.',
                      ),
                      const SizedBox(height: 24),
                      if (_creatingAccount) ...[
                        TextFormField(
                          controller: _nameController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Full name'),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _studentIdController,
                          decoration: const InputDecoration(labelText: 'PSU student ID'),
                          validator: _required,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _department,
                          decoration: const InputDecoration(labelText: 'Department'),
                          items: const [
                            'IT',
                            'Engineering',
                            'Architecture',
                            'Nursing',
                            'Business',
                          ]
                              .map((department) => DropdownMenuItem(
                                    value: department,
                                    child: Text(department),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value != null) setState(() => _department = value);
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Student email'),
                        validator: (value) {
                          if (value == null || !value.contains('@')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) => value == null || value.length < 8
                            ? 'Use at least 8 characters.'
                            : null,
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 14),
                        Text(_message!, style: const TextStyle(color: Color(0xFF047857))),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(_creatingAccount ? 'Create account' : 'Sign in'),
                        ),
                      ),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton(
                          onPressed: _submitting
                              ? null
                              : () => setState(() {
                                    _creatingAccount = !_creatingAccount;
                                    _error = null;
                                    _message = null;
                                  }),
                          child: Text(_creatingAccount
                              ? 'I already have an account'
                              : 'Create a borrower account'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;
}

class _ProfileSetupError extends StatelessWidget {
  const _ProfileSetupError({
    required this.client,
    required this.message,
    required this.onRetry,
  });

  final SupabaseClient client;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.school_outlined, size: 40),
                  const SizedBox(height: 16),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: onRetry, child: const Text('Try again')),
                  TextButton(
                    onPressed: client.auth.signOut,
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}