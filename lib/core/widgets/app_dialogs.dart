import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Kumpulan helper dialog bergaya iOS agar semua fitur memakai pola yang sama.
class AppDialogs {
  const AppDialogs._();

  /// Alert dengan satu tombol OK.
  static Future<void> alert(
    BuildContext context, {
    required String title,
    String? message,
    String okLabel = 'OK',
  }) {
    return showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(okLabel),
          ),
        ],
      ),
    );
  }

  /// Konfirmasi dua tombol. Mengembalikan `true` jika user memilih aksi.
  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    String? message,
    required String confirmLabel,
    String cancelLabel = 'Batal',
    bool destructive = false,
  }) async {
    final result = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: message == null ? null : Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            isDefaultAction: !destructive,
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// Action sheet iOS. Mengembalikan nilai dari opsi yang dipilih, atau `null`
  /// jika dibatalkan.
  static Future<T?> actionSheet<T>(
    BuildContext context, {
    String? title,
    String? message,
    required List<ActionSheetOption<T>> options,
    String cancelLabel = 'Batal',
  }) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: CupertinoActionSheet(
              title: title == null ? null : Text(title),
              message: message == null ? null : Text(message),
              actions: [
                for (final o in options)
                  CupertinoActionSheetAction(
                    isDestructiveAction: o.destructive,
                    onPressed: () => Navigator.pop(ctx, o.value),
                    child: Text(o.label),
                  ),
              ],
              cancelButton: CupertinoActionSheetAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: Text(cancelLabel),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Bottom sheet dengan handle, sudut membulat, dan animasi pegas.
  /// Di layar lebar lebarnya dibatasi supaya tidak membentang penuh.
  static Future<T?> sheet<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    double maxWidth = 640,
  }) {
    final c = context.colors;
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.cardElevated,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      constraints: BoxConstraints(maxWidth: maxWidth),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      sheetAnimationStyle: AnimationStyle(
        duration: AppDurations.slow,
        reverseDuration: AppDurations.medium,
        curve: SpringCurve.smooth,
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Text(
                title,
                style: AppTypography.title3.copyWith(color: ctx.colors.label),
              ),
            ),
          Flexible(child: builder(ctx)),
        ],
      ),
    );
  }
}

class ActionSheetOption<T> {
  const ActionSheetOption({
    required this.label,
    required this.value,
    this.destructive = false,
  });

  final String label;
  final T value;
  final bool destructive;
}

/// Garis kecil di atas sheet sebagai penanda bisa diseret.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(
          top: AppSpacing.xs,
          bottom: AppSpacing.xs,
        ),
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: context.colors.labelTertiary,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}
