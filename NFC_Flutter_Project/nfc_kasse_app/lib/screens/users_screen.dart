import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_model.dart';
import '../providers/providers.dart';
import '../widgets/dialogs/edit_user_dialog.dart';

final _usersListProvider = FutureProvider.autoDispose<List<UserListItem>>((ref) {
  return ref.read(usersServiceProvider).getUsers();
});

/// Lists all users in the current tenant and allows the admin to create or edit
/// them. Opening the edit button on a row launches [EditUserDialog]. The list
/// is invalidated when the dialog returns `true` (a change was made).
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(_usersListProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: theme.colorScheme.surfaceContainerHigh,
          child: Row(
            children: [
              Text('Benutzerverwaltung', style: theme.textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _openDialog(context, ref, null),
                icon: const Icon(Icons.person_add_outlined, size: 18),
                label: const Text('Neu'),
              ),
            ],
          ),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Fehler: $e')),
            data: (users) => users.isEmpty
                ? const Center(child: Text('Keine Benutzer'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: users.length,
                    separatorBuilder: (_, i) => const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) {
                      final user = users[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: user.active
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerHighest,
                          child: Text(
                            (user.displayName ?? user.username)
                                .substring(0, 1)
                                .toUpperCase(),
                            style: TextStyle(
                              color: user.active
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        title: Text(
                          user.displayLabel,
                          style: TextStyle(
                            color: user.active ? null : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        subtitle: user.displayName != null
                            ? Text(
                                user.username,
                                style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant),
                              )
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!user.active)
                              Chip(
                                label: const Text('Inaktiv'),
                                visualDensity: VisualDensity.compact,
                                labelStyle: const TextStyle(fontSize: 11),
                              ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              onPressed: () => _openDialog(context, ref, user),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _openDialog(
      BuildContext context, WidgetRef ref, UserListItem? user) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => EditUserDialog(user: user),
    );
    if (result == true) {
      ref.invalidate(_usersListProvider);
    }
  }
}
