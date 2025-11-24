import 'package:flutter/material.dart';

class ScrollableMetricsText extends StatelessWidget {
  const ScrollableMetricsText({
    super.key,
    required this.text,
    this.backgroundColor,
  });

  final String text;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = Theme.of(context).textTheme.bodyMedium;

    return LayoutBuilder(
      builder: (context, constraints) {
        final style = defaultStyle ?? DefaultTextStyle.of(context).style;
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(minWidth: 0, maxWidth: double.infinity);

        final overflow = painter.size.width > constraints.maxWidth;
        final scrollView = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          physics: overflow
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                text,
                style: style,
                textAlign: TextAlign.right,
                softWrap: false,
              ),
            ),
          ),
        );

        if (!overflow) {
          return scrollView;
        }

        final Color baseColor =
            backgroundColor ??
            CardTheme.of(context).color ??
            Theme.of(context).colorScheme.surface;

        return Stack(
          children: [
            scrollView,
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 20,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [baseColor.withValues(alpha: 0), baseColor],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
