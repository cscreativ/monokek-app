import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/api/envelope.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/brand_logo.dart';
import 'auth_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final user = await ref.read(authProvider.notifier).login(_email.text.trim(), _password.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bienvenue, ${user.name}')));
      // Router redirect sends the user to their role's home.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMessage(e)), backgroundColor: Theme.of(context).colorScheme.error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/setup'),
        tooltip: 'Réglages système',
        shape: const CircleBorder(),
        child: const Icon(LucideIcons.settings),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const BrandLogo(subtitle: 'Accès Professionnel'),
              const SizedBox(height: 32),
              Card(
                elevation: 8,
                shadowColor: Colors.black26,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Form(
                    key: _form,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Connexion', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Entrez vos identifiants pour accéder à votre session.', style: TextStyle(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 20),
                      Text('EMAIL', style: microLabelStyle.copyWith(color: scheme.onSurface)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: 'nom@mono-kek.com', prefixIcon: Icon(LucideIcons.user, size: 18)),
                        validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? 'Email invalide' : null,
                      ),
                      const SizedBox(height: 16),
                      Text('MOT DE PASSE', style: microLabelStyle.copyWith(color: scheme.onSurface)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _password,
                        obscureText: !_show,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _loading ? null : _submit(),
                        decoration: InputDecoration(
                          prefixIcon: const Icon(LucideIcons.lock, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(_show ? LucideIcons.eyeOff : LucideIcons.eye, size: 18),
                            onPressed: () => setState(() => _show = !_show),
                          ),
                        ),
                        validator: (v) => (v == null || v.length < 4) ? 'Le mot de passe est trop court' : null,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                SizedBox(width: 12),
                                Text('AUTHENTIFICATION...'),
                              ])
                            : const Text('SE CONNECTER'),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'BESOIN D\'AIDE ? CONTACTEZ VOTRE ADMINISTRATEUR DE SUCCURSALE.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
