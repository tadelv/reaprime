import 'package:flutter/material.dart';
import 'package:reaprime/src/account/decent_login_form.dart';
import 'package:reaprime/src/services/account/decent_account_service.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    required this.accountService,
  });

  static const routeName = '/account';

  final DecentAccountService accountService;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Decent Account')),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: FutureBuilder<bool>(
            future: widget.accountService.isLoggedIn(),
            builder: (context, snapshot) {
              final loggedIn = snapshot.data ?? false;

              if (loggedIn) {
                return FutureBuilder<String?>(
                  future: widget.accountService.getEmail(),
                  builder: (context, emailSnap) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ShadCard(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.account_circle, size: 40),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Logged In',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          Text(
                                            emailSnap.data ?? '',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ShadButton.destructive(
                                  onPressed: () async {
                                    await widget.accountService.logout();
                                    setState(() {});
                                  },
                                  child: const Text('Unlink Account'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              }

              return ShadCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Link Your Account',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Link your Decent Espresso account to verify your machine serial number and access additional features.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                      const SizedBox(height: 16),
                      DecentLoginForm(
                        accountService: widget.accountService,
                        onSuccess: () => setState(() {}),
                        secondaryLabel: 'Cancel',
                        onSecondary: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
