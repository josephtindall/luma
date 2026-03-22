import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _palette = [
  Color(0xFF1A73E8), // blue
  Color(0xFF0D652D), // green
  Color(0xFFE8710A), // orange
  Color(0xFFC5221F), // red
  Color(0xFF7B1FA2), // purple
  Color(0xFF00838F), // teal
  Color(0xFFD81B60), // pink
  Color(0xFF4E342E), // brown
  Color(0xFF546E7A), // blue-grey
  Color(0xFF2E7D32), // dark green
  Color(0xFF6A1B9A), // deep purple
  Color(0xFFEF6C00), // deep orange
];

class UserAvatar extends StatelessWidget {
  final String avatarSeed;
  final String displayName;
  final double size;

  const UserAvatar({
    super.key,
    required this.avatarSeed,
    required this.displayName,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFromSeed(avatarSeed);
    final initials = _initials(displayName);

    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        initials,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static Color _colorFromSeed(String seed) {
    var hash = 0;
    for (final c in seed.codeUnits) {
      hash += c;
    }
    return _palette[hash % _palette.length];
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
