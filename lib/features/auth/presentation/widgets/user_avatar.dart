import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/app_user.dart';
import '../../domain/user_role.dart';

extension UserRoleStyle on UserRole {
  /// Admin biru, supervisor ungu, kasir hijau: dipakai konsisten di login
  /// dan sidebar.
  Color color(AppColors c) => switch (this) {
    UserRole.admin => c.accent,
    UserRole.supervisor => c.purple,
    UserRole.kasir => c.success,
  };

  IconData get icon => switch (this) {
    UserRole.admin => CupertinoIcons.person_badge_plus_fill,
    UserRole.supervisor => CupertinoIcons.cube_box_fill,
    UserRole.kasir => CupertinoIcons.cart_fill,
  };
}

/// Lingkaran inisial berwarna sesuai peran.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.size = 36});

  final AppUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = user.role.color(c);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.75), color],
        ),
      ),
      child: Text(
        user.initials,
        style: AppTypography.headline.copyWith(
          color: CupertinoColors.white,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

/// Label kecil "Admin" / "Supervisor" / "Kasir".
class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    final color = role.color(context.colors);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.icon, size: 11, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              role.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
