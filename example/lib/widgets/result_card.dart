import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResultCard extends StatelessWidget {
  final String title;
  final String result;
  final bool isError;

  const ResultCard({
    super.key,
    required this.title,
    required this.result,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      color: isError
          ? colorScheme.errorContainer
          : colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.check_circle_outline,
                  color: isError
                      ? colorScheme.onErrorContainer
                      : colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: isError
                        ? colorScheme.onErrorContainer
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: result));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Copied to clipboard'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  tooltip: 'Copy to clipboard',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isError
                    ? colorScheme.error.withOpacity(0.1)
                    : colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                result,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: isError
                      ? colorScheme.onErrorContainer
                      : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
