import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/audio_provider.dart';

/// Self-contained settings card for the audio module.
///
/// This widget provides a toggle to enable/disable the audio module.
/// Drop it into any settings/profile screen with minimal integration.
///
/// Usage:
/// ```dart
/// // In profile_screen.dart or settings screen
/// AudioSettingsCard()
/// ```
class AudioSettingsCard extends StatelessWidget {
  const AudioSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = context.watch<AudioProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.headphones, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Audio Module',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (audioProvider.isEnabled)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Beta',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Enable Audiobooks'),
            subtitle: Text(
              audioProvider.isEnabled
                  ? 'Automatically search for free audiobook versions'
                  : 'Discover free audiobooks from LibriVox & others',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: audioProvider.isEnabled,
            onChanged: (value) => audioProvider.setEnabled(value),
          ),
          if (audioProvider.isEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        audioProvider.isWifiConnected
                            ? Icons.wifi
                            : Icons.wifi_off,
                        size: 16,
                        color: audioProvider.isWifiConnected
                            ? Colors.green
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        audioProvider.isWifiConnected
                            ? 'WiFi connected — streaming available'
                            : 'Connect to WiFi to stream audiobooks',
                        style: TextStyle(
                          fontSize: 12,
                          color: audioProvider.isWifiConnected
                              ? Colors.green
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildSourceChip(context, 'LibriVox'),
                      _buildSourceChip(context, 'Littérature Audio'),
                      _buildSourceChip(context, 'Archive.org'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceChip(BuildContext context, String label) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
