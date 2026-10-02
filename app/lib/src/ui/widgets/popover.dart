// A small panel anchored to a button (password generator, link editor).
import 'package:flutter/material.dart';

import '../theme.dart';
import 'common.dart';

class PopoverButton extends StatefulWidget {
  const PopoverButton({
    super.key,
    required this.icon,
    required this.builder,
    this.tooltip,
    this.active = false,
    this.width = 300,
  });

  final IconData icon;
  final String? tooltip;
  final bool active;
  final double width;

  /// Builds the panel; call `close` to dismiss it.
  final Widget Function(BuildContext context, VoidCallback close) builder;

  @override
  State<PopoverButton> createState() => _PopoverButtonState();
}

class _PopoverButtonState extends State<PopoverButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _close() {
    if (_controller.isShowing) _controller.hide();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (ctx) => Stack(children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _close)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: widget.width,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.divider),
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 8))],
                ),
                child: Theme(data: Theme.of(context), child: widget.builder(ctx, _close)),
              ),
            ),
          ),
        ]),
        child: VIconButton(
          icon: widget.icon,
          tooltip: widget.tooltip,
          active: widget.active || _controller.isShowing,
          size: 15,
          onPressed: () => setState(() => _controller.toggle()),
        ),
      ),
    );
  }
}
