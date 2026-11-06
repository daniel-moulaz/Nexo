import 'package:timezone/data/latest_all.dart' as tz_data;

bool _ready = false;

/// The time zone database is parsed from scratch on every call, and it sits
/// in front of the first screen: load it once for all the reminder services.
void ensureTimeZones() {
  if (_ready) return;
  tz_data.initializeTimeZones();
  _ready = true;
}
