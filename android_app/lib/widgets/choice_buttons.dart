import 'package:flutter/material.dart';

import '../theme.dart';

/// A parsed choice option from an agent response (e.g. "A) Use SymPy").
class ParsedChoice {
  final String label;
  final String text;

  const ParsedChoice({required this.label, required this.text});
}

/// Extracts A/B/C/D style choices from agent response text.
///
/// Matches patterns like:
///   A) Some option text
///   B. Another option
///   **A.** Bold option
///   1. Numbered option
///   2) Another numbered
List<ParsedChoice> parseChoices(String text) {
  final choices = <ParsedChoice>[];

  final pattern = RegExp(
    r'(?:^|\n)\s*(?:\*\*)?([A-Da-d1-4])[.)]\)?(?:\*\*)?\s+(.+?)(?=\n|$)',
    multiLine: true,
  );

  for (final match in pattern.allMatches(text)) {
    final label = match.group(1)!.toUpperCase();
    final optionText = match.group(2)!.trim();
    if (optionText.isNotEmpty) {
      choices.add(ParsedChoice(label: label, text: optionText));
    }
  }

  // Only return if we found 2-6 choices (likely a real question)
  if (choices.length >= 2 && choices.length <= 6) {
    return choices;
  }
  return [];
}

/// Renders tappable choice buttons for A/B/C/D options.
///
/// When a choice is tapped, [onChoice] is called with the full choice text
/// so it can be sent as the user's next message.
class ChoiceButtons extends StatelessWidget {
  final List<ParsedChoice> choices;
  final void Function(String choiceText) onChoice;

  const ChoiceButtons({
    super.key,
    required this.choices,
    required this.onChoice,
  });

  @override
  Widget build(BuildContext context) {
    if (choices.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 48, top: 4, bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: choices.map((choice) {
          return ActionChip(
            avatar: CircleAvatar(
              radius: 12,
              backgroundColor: AppTheme.neonGreen,
              child: Text(
                choice.label,
                style: const TextStyle(
                  color: AppTheme.backgroundDark,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            label: Text(
              choice.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 13),
            ),
            backgroundColor: AppTheme.mutedGreen,
            side: const BorderSide(color: AppTheme.darkGreen, width: 0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            onPressed: () => onChoice('${choice.label}) ${choice.text}'),
          );
        }).toList(),
      ),
    );
  }
}
