import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/backend_cli.dart';
import '../services/tenants_service.dart';

/// Veranstalter: komplett getrennte Kassen auf demselben Server, eine
/// nach der anderen benutzt. Jeder hat eigene Benutzer, Rechte,
/// Warengruppen, Artikel, Chips mit Guthaben und Feste. Aktiv ist immer
/// genau einer — nur dessen Benutzer können sich anmelden.
class TenantsScreen extends ConsumerStatefulWidget {
  const TenantsScreen({super.key});

  @override
  ConsumerState<TenantsScreen> createState() => _TenantsScreenState();
}

class _TenantsScreenState extends ConsumerState<TenantsScreen> {
  bool _busy = false;

  void _refreshAll() {
    ref.read(tenantsRefreshProvider.notifier).state++;
    ref.read(eventsRefreshProvider.notifier).state++;
    ref.read(backupRefreshProvider.notifier).state++;
  }

  Future<void> _run(String progress, Future<String> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    messenger.showSnackBar(SnackBar(content: Text(progress)));
    try {
      final done = await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } on BackendCliException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      _refreshAll();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _create() async {
    final result = await showDialog<({String name, String user, String password})>(
      context: context,
      builder: (_) => const _CreateTenantDialog(),
    );
    if (result == null) return;
    await _run('Veranstalter wird angelegt …', () async {
      final t = await TenantsService.create(name: result.name, adminUser: result.user, adminPassword: result.password);
      return 'Veranstalter „${t.name}“ angelegt. Zum Benutzen auf „Aktivieren“ klicken.';
    });
  }

  Future<void> _activate(TenantInfo tenant) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Zu „${tenant.name}“ wechseln?'),
        content: SizedBox(
          width: 460,
          child: Text(
            'Danach ist die Kasse von „${tenant.name}“ in Betrieb: deren Benutzer, Warengruppen, Artikel, '
            'Chips und Feste. Alle Kassen werden abgemeldet und melden sich mit einem Konto dieses '
            'Veranstalters neu an.\n\n'
            'Das geht nur, wenn gerade kein Fest läuft. Vorher wird automatisch gesichert.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wechseln')),
        ],
      ),
    );
    if (ok != true) return;
    await _run('Wechsel wird vorbereitet, vorher wird gesichert …', () async {
      await TenantsService.activate(tenant.id);
      return '„${tenant.name}“ ist jetzt aktiv. Alle Kassen sind abgemeldet.';
    });
  }

  Future<void> _rename(TenantInfo tenant) async {
    final controller = TextEditingController(text: tenant.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Veranstalter umbenennen'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Speichern')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || name == tenant.name) return;
    await _run('Wird umbenannt …', () async {
      await TenantsService.rename(tenant.id, name);
      return 'Umbenannt in „$name“.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tenantsAsync = ref.watch(tenantsProvider);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(child: Text('Veranstalter', style: theme.textTheme.headlineSmall)),
            FilledButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Neuer Veranstalter'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Jeder Veranstalter ist eine eigene Kasse mit eigenen Benutzern, Rechten, Warengruppen, Artikeln, '
          'Chips und Festen. In Betrieb ist immer einer, nur dessen Benutzer können sich anmelden.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline),
        ),
        const SizedBox(height: 16),
        tenantsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Veranstalter konnten nicht geladen werden: $e'),
          data: (tenants) => Column(
            children: [
              for (final t in tenants)
                Card(
                  child: ListTile(
                    leading: Icon(
                      t.active ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: t.active ? theme.colorScheme.primary : null,
                    ),
                    title: Text(t.active ? '${t.name} · in Betrieb' : t.name),
                    subtitle: Text([
                      'Läuft: ${t.running ?? '—'}',
                      '${t.users} Benutzer',
                      '${t.categories} Warengruppen',
                      '${t.fests} Feste',
                    ].join('  ·  ')),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Umbenennen',
                          onPressed: _busy ? null : () => _rename(t),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        if (!t.active)
                          OutlinedButton(
                            onPressed: _busy ? null : () => _activate(t),
                            child: const Text('Aktivieren'),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CreateTenantDialog extends StatefulWidget {
  const _CreateTenantDialog();

  @override
  State<_CreateTenantDialog> createState() => _CreateTenantDialogState();
}

class _CreateTenantDialogState extends State<_CreateTenantDialog> {
  final _name = TextEditingController();
  final _user = TextEditingController(text: 'admin');
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _user, _password, _repeat]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    String? error;
    if (_name.text.trim().isEmpty) {
      error = 'Bitte einen Namen eingeben.';
    } else if (_user.text.trim().isEmpty) {
      error = 'Bitte einen Benutzernamen für den Administrator eingeben.';
    } else if (_password.text.length < 6) {
      error = 'Das Passwort muss mindestens 6 Zeichen haben.';
    } else if (_password.text != _repeat.text) {
      error = 'Die Passwörter stimmen nicht überein.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (name: _name.text.trim(), user: _user.text.trim(), password: _password.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Neuer Veranstalter'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Name *')),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(
                labelText: 'Benutzername des Administrators *',
                helperText: 'Mit diesem Konto richtet der Veranstalter seine Kasse ein.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort * (mindestens 6 Zeichen)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Passwort wiederholen *'),
              onSubmitted: (_) => _submit(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen')),
        FilledButton(onPressed: _submit, child: const Text('Anlegen')),
      ],
    );
  }
}
