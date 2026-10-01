/// Aturan isian akun. Dipakai form (pesan per kolom) dan repository
/// (pemeriksaan akhir sebelum menyimpan).
class AccountRules {
  const AccountRules._();

  static const minPasswordLength = 6;
  static final _usernamePattern = RegExp(r'^[a-z0-9._]+$');

  /// Username disimpan tanpa spasi tepi dan dalam huruf kecil.
  static String normalizeUsername(String value) => value.trim().toLowerCase();

  static String? username(String value) {
    final v = normalizeUsername(value);
    if (v.isEmpty) return 'Username wajib diisi.';
    if (v.length < 3 || v.length > 32) return 'Username 3–32 karakter.';
    if (!_usernamePattern.hasMatch(v)) {
      return 'Hanya huruf, angka, titik, atau garis bawah (tanpa spasi).';
    }
    return null;
  }

  static String? fullName(String value) {
    final v = value.trim();
    if (v.isEmpty) return 'Nama wajib diisi.';
    if (v.length > 100) return 'Nama maksimal 100 karakter.';
    return null;
  }

  static String? password(String value) {
    if (value.isEmpty) return 'Password wajib diisi.';
    if (value.length < minPasswordLength) {
      return 'Password minimal $minPasswordLength karakter.';
    }
    return null;
  }

  static String? confirmPassword(String password, String confirm) {
    if (confirm != password) return 'Konfirmasi password tidak sama.';
    return null;
  }
}
