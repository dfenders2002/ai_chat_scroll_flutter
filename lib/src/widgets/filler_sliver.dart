import 'package:flutter/widgets.dart';

/// Internal widget that renders a dynamic filler space below the message list.
///
/// Isolated via [ValueListenableBuilder] so that filler height changes (driven
/// by Phase 3 streaming token logic) do NOT trigger rebuilds of the message
/// list items above it.
///
/// This widget is intentionally NOT exported from the package barrel. It is an
/// implementation detail of [AiChatScrollView].
class FillerSliver extends StatelessWidget {
  /// Creates a [FillerSliver].
  ///
  /// [fillerHeight] is a [ValueNotifier] whose value sets the height of the
  /// filler [SizedBox]. When the value changes, only this widget rebuilds —
  /// the parent [SliverList.builder] is unaffected.
  const FillerSliver({super.key, required this.fillerHeight});

  /// The notifier driving filler height. Initialized to 0.0 in Phase 2.
  /// Phase 3 will update this value during streaming to maintain top-anchor
  /// layout.
  final ValueNotifier<double> fillerHeight;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fillerHeight,
      builder: (context, height, _) => SizedBox(height: height),
    );
  }
}
