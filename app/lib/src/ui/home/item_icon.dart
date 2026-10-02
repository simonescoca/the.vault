// List icon: the site's icon when the entry has a website, otherwise its initial.
import 'package:flutter/material.dart';

import '../../core/favicon/favicon_service.dart';
import '../../core/model/item.dart';
import '../theme.dart';

class ItemIcon extends StatelessWidget {
  const ItemIcon({super.key, required this.item, required this.favicons, this.size = 28});

  final Item item;
  final FaviconService? favicons;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final site = item.website;
    final f = favicons;
    if (site != null && f != null) {
      return ListenableBuilder(
        listenable: f,
        builder: (context, _) {
          final bytes = f.icon(FaviconService.domainOf(site));
          if (bytes == null) return _initial(context, c);
          return Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(size * 0.25),
              border: Border.all(color: c.divider),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.12),
              child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium, gaplessPlayback: true),
            ),
          );
        },
      );
    }
    return _initial(context, c);
  }

  Widget _initial(BuildContext context, VaultColors c) {
    final t = item.title.trim();
    final letter = t.isEmpty ? '•' : t.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.selected, borderRadius: BorderRadius.circular(size * 0.25)),
      child: Text(letter, style: TextStyle(fontFamily: kSans, fontSize: size * 0.46, fontWeight: FontWeight.w600, color: c.text2, height: 1)),
    );
  }
}
