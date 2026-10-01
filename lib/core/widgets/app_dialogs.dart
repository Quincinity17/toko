import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import '../utils/number_input.dart';

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

  /// Meminta satu angka (qty, persen, dll.) dengan alert iOS berisi field.
  /// Mengembalikan `null` jika dibatalkan atau isian tidak valid.
  static Future<double?> promptNumber(
    BuildContext context, {
    required String title,
    String? message,
    required double initial,
    String? suffix,
    double min = 0,
    double? max,
  }) {
    final controller = TextEditingController(text: Fmt.number(initial));
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    return showCupertinoDialog<double>(
      context: context,
      builder: (ctx) {
        void submit() {
          final v = parseIdNumber(controller.text);
          if (v == null || v < min || (max != null && v > max)) return;
          Navigator.pop(ctx, v);
        }

        return CupertinoAlertDialog(
          title: Text(title),
          content: Column(
            children: [
              if (message != null) Text(message),
              const SizedBox(height: AppSpacing.sm),
              CupertinoTextField(
                controller: controller,
                autofocus: true,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                suffix: suffix == null
                    ? null
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(suffix),
                      ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: submit,
              child: const Text('Simpan'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
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

  /// Popup di tengah layar (kartu membulat, muncul dengan animasi pegas).
  /// Tidak tertutup saat klik di luar; tutup dengan tombol ✕ atau Esc.
  ///
  /// Isi [autofocusRoot] `false` jika isi popup punya field `autofocus`
  /// (agar fokus jatuh ke field itu, bukan ke kerangka popup).
  static Future<T?> popup<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    String? title,
    double maxWidth = 480,
    bool autofocusRoot = true,
  }) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierLabel: title ?? 'Popup',
      barrierColor: Colors.black.withValues(alpha: 0.3),
      transitionDuration: AppDurations.medium,
      pageBuilder: (ctx, _, _) => _Popup(
        title: title,
        maxWidth: maxWidth,
        autofocusRoot: autofocusRoot,
        child: Builder(builder: builder),
      ),
      transitionBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: SpringCurve.smooth,
          reverseCurve: Curves.easeIn,
        );
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween(begin: 0.94, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// Memilih tanggal dengan roda tanggal iOS di dalam popup.
  /// Mengembalikan tanggal terpilih, atau `null` jika dibatalkan.
  static Future<DateTime?> pickDate(
    BuildContext context, {
    required String title,
    DateTime? initial,
  }) {
    var selected = initial ?? DateTime.now();
    return popup<DateTime>(
      context,
      title: title,
      maxWidth: 380,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 200,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: selected,
                dateOrder: DatePickerDateOrder.dmy,
                onDateTimeChanged: (d) => selected = d,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: () => Navigator.pop(ctx, selected),
                child: const Text('Pilih Tanggal'),
              ),
            ),
          ],
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

class _Popup extends StatelessWidget {
  const _Popup({
    required this.title,
    required this.maxWidth,
    required this.autofocusRoot,
    required this.child,
  });

  final String? title;
  final double maxWidth;
  final bool autofocusRoot;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = MediaQuery.sizeOf(context);

    // Esc menutup popup walau klik di luar tidak (barrierDismissible: false).
    return Actions(
      actions: {
        DismissIntent: CallbackAction<DismissIntent>(
          onInvoke: (_) => Navigator.of(context).maybePop(),
        ),
      },
      child: Focus(
        autofocus: autofocusRoot,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: maxWidth,
                  maxHeight: size.height * 0.9,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: AppRadius.xlAll,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 40,
                        offset: const Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Material(
                    color: c.cardElevated,
                    borderRadius: AppRadius.xlAll,
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.md,
                            AppSpacing.sm,
                            AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title ?? '',
                                  style: AppTypography.title3.copyWith(
                                    color: c.label,
                                  ),
                                ),
                              ),
                              Tooltip(
                                message: 'Tutup (Esc)',
                                child: CupertinoButton(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(36, 36),
                                  onPressed: () =>
                                      Navigator.of(context).maybePop(),
                                  child: Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: c.fill,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      CupertinoIcons.xmark,
                                      size: 14,
                                      color: c.labelSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Flexible(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
