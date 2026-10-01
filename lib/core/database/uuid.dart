import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// ID unik global (UUID v4) untuk data yang disinkron antar komputer.
/// Id angka (`id`) tetap dipakai di dalam satu database; `uuid` dipakai
/// untuk mengenali baris yang sama di server dan di komputer lain.
String newUuid() => _uuid.v4();
