import 'package:flutter/cupertino.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/pressable_scale.dart';
import '../../domain/app_user.dart';
import '../../domain/user_role.dart';

extension UserRoleStyle on UserRole {
  /// Admin biru, kasir hijau: dipakai konsisten di login dan sidebar.
  Color color(AppColors c) => switch (this) {
    UserRole.admin => c.accent,
    UserRole.kasir => c.success,
  };

  IconData get icon => switch (this) {
    UserRole.admin => CupertinoIcons.person_badge_plus_fill,
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

/// Label kecil "Admin" / "Kasir".
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
          Text(
            role.label,
            style: AppTypography.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu akun di layar login: avatar besar, nama, dan label peran.
class UserTile extends StatelessWidget {
  const UserTile({
    super.key,
    required this.user,
    required this.selected,
    this.onPressed,
  });

  final AppUser user;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = user.role.color(c);
    return PressableScale(
      onPressed: onPressed,
      pressedScale: 0.95,
      borderRadius: AppRadius.lgAll,
      child: AnimatedContainer(
        duration: AppDurations.medium,
        curve: SpringCurve.smooth,
        width: 132,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : c.fillSecondary,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: selected ? color : const Color(0x00000000),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.06 : 1,
              duration: AppDurations.medium,
              curve: SpringCurve.bouncy,
              child: UserAvatar(user: user, size: 56),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              user.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: AppTypography.subheadline.copyWith(
                color: c.label,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            RoleBadge(role: user.role),
          ],
        ),
      ),
    );
  }
}
