import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:reaprime/src/home_feature/home_feature.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';
import 'package:reaprime/src/webui_support/webui_storage.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class LandingFeature extends StatefulWidget {
  static const routeName = '/landing';
  final WebUIStorage webUIStorage;
  final WebUIService webUIService;

  const LandingFeature({
    super.key,
    required this.webUIStorage,
    required this.webUIService,
  });

  @override
  State<StatefulWidget> createState() => _LandingState();
}

class _LandingState extends State<LandingFeature> {
  final _log = Logger('LandingFeature');

  WebUISkin? _selectedSkin;
  bool _isLoading = true;
  bool _isServingUI = false;
  String? _errorMessage;
  Timer? _autoNavigateTimer;
  int _remainingSeconds = 30;

  static const String _selectedSkinPrefKey = 'selected_webui_skin_id';

  @override
  void initState() {
    super.initState();
    _initializeLanding();
  }

  @override
  void dispose() {
    _autoNavigateTimer?.cancel();
    super.dispose();
  }

  Future<void> _initializeLanding() async {
    try {
      // Get available skins
      final skins = widget.webUIStorage.installedSkins;

      if (skins.isEmpty) {
        setState(() {
          _errorMessage = 'No WebUI skins available. Please install a skin.';
          _isLoading = false;
        });
        return;
      }

      // Check if WebUI service is already serving (initialized in PermissionsView)
      if (widget.webUIService.isServing) {
        _log.info('WebUI service already serving, using current skin');
        // Try to determine which skin is being served (use default)
        final defaultSkin = widget.webUIStorage.defaultSkin;
        setState(() {
          _selectedSkin = defaultSkin;
          _isServingUI = true;
          _isLoading = false;
        });
      } else {
        // WebUI not serving - show error message explaining the issue
        setState(() {
          _errorMessage = 
              'WebUI service failed to start during initialization. '
              'This may be due to missing skins or port conflicts. '
              'You can still use the dashboard below.';
          _isLoading = false;
        });
      }
    } catch (e, st) {
      _log.severe('Failed to initialize landing', e, st);
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _serveSkin(WebUISkin skin) async {
    setState(() {
      _isServingUI = true;
      _errorMessage = null;
    });

    try {
      // Serve the selected skin
      await widget.webUIService.serveFolderAtPath(skin.path, port: 3000);

      _log.info(
        'Now serving WebUI skin: ${skin.name} at http://localhost:3000',
      );

      setState(() {
        _selectedSkin = skin;
        _isServingUI = false;
      });

      // Save preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedSkinPrefKey, skin.id);

      // Start auto-navigate timer
      _startAutoNavigateTimer();
    } catch (e, st) {
      _log.severe('Failed to serve WebUI skin', e, st);
      setState(() {
        _errorMessage = 'Failed to serve skin: $e';
        _isServingUI = false;
      });
    }
  }

  void _startAutoNavigateTimer() {
    _autoNavigateTimer?.cancel();
    setState(() {
      _remainingSeconds = 30;
    });

    _autoNavigateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _remainingSeconds--;
      });

      if (_remainingSeconds <= 0) {
        timer.cancel();
        _navigateToHome();
      }
    });
  }

  void _navigateToHome() {
    if (mounted) {
      Navigator.pushReplacementNamed(context, HomeScreen.routeName);
    }
  }

  Future<void> _openInBrowser() async {
    _autoNavigateTimer?.cancel();

    try {
      final url = Uri.parse('http://localhost:3000');
      await launchUrl(url);

      // Still navigate to home after opening browser
      _navigateToHome();
    } catch (e, st) {
      _log.severe('Failed to launch URL', e, st);
      setState(() {
        _errorMessage = 'Failed to open browser: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streamline Setup'),
        actions: [
          TextButton(
            onPressed: _navigateToHome,
            child: const Text('Skip to Dashboard'),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (_isLoading)
                const CircularProgressIndicator()
              else if (_errorMessage != null)
                _buildErrorView()
              else if (widget.webUIStorage.installedSkins.isEmpty)
                _buildNoSkinsView()
              else if (!_isServingUI && _selectedSkin == null)
                _buildSkinSelectionView()
              else if (_isServingUI)
                _buildLoadingView()
              else if (_selectedSkin != null && widget.webUIService.isServing)
                _buildServingView()
              else
                _buildSkinSelectionView(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 64, color: Colors.red),
        const SizedBox(height: 16),
        Text(
          _errorMessage!,
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ShadButton(
          onPressed: _navigateToHome,
          child: const Text('Continue to Dashboard'),
        ),
      ],
    );
  }

  Widget _buildNoSkinsView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.web_asset_off, size: 64),
        const SizedBox(height: 16),
        Text(
          'No Skins available',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Please install a skin to use this feature.',
          style: Theme.of(context).textTheme.bodyLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ShadButton(
          onPressed: _navigateToHome,
          child: const Text('Continue to Dashboard'),
        ),
      ],
    );
  }

  Widget _buildLoadingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(
          'Starting WebUI server...',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }

  Widget _buildSkinSelectionView() {
    final skins = widget.webUIStorage.installedSkins;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Icon(Icons.web, size: 64),
        const SizedBox(height: 16),
        Text(
          'Select Skin',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a skin to customize your web interface',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600, maxHeight: 400),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: skins.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final skin = skins[index];
              final isSelected = _selectedSkin?.id == skin.id;

              return Card(
                elevation: isSelected ? 4 : 1,
                color:
                    isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                child: ListTile(
                  leading: Icon(
                    skin.isBundled ? Icons.star : Icons.web_asset,
                    color: skin.isBundled ? Colors.amber : null,
                  ),
                  title: Text(skin.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (skin.description != null) Text(skin.description!),
                      if (skin.version != null)
                        Text(
                          'Version: ${skin.version}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (skin.reaMetadata?.sourceUrl != null)
                        Text(
                          'Source: ${_formatSourceUrl(skin.reaMetadata!.sourceUrl!)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  trailing:
                      isSelected
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : null,
                  selected: isSelected,
                  onTap: () => _serveSkin(skin),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 24),
        ShadButton.secondary(
          onPressed: _navigateToHome,
          child: const Text('Skip'),
        ),
      ],
    );
  }

  Widget _buildServingView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, size: 64, color: Colors.green),
        const SizedBox(height: 16),
        Text('Skin Ready!', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Serving: ${_selectedSkin!.name}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'http://localhost:3000',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 24),
        ShadButton(
          onPressed: _openInBrowser,
          child: const Text('Open in Browser'),
        ),
        const SizedBox(height: 16),
        ShadButton.secondary(
          onPressed: _navigateToHome,
          child: const Text('Continue to Dashboard'),
        ),
        const SizedBox(height: 24),
        Text(
          'Auto-navigating to Dashboard in $_remainingSeconds seconds...',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 200,
          child: LinearProgressIndicator(value: _remainingSeconds / 30),
        ),
      ],
    );
  }

  String _formatSourceUrl(String url) {
    // Simplify GitHub URLs for display
    final match = RegExp(r'github\.com/([^/]+)/([^/]+)').firstMatch(url);
    if (match != null) {
      return 'GitHub: ${match.group(1)}/${match.group(2)}';
    }
    return url;
  }
}

