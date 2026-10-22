/// Name this plugin reports to the Rivium backend as its SDK identity
/// (`X-Rivium-SDK: flutter/<version> android|ios/<native version>`).
const String riviumSyncSdkName = 'flutter';

/// Version of the rivium_sync plugin.
///
/// Must match `version` in pubspec.yaml (enforced by a unit test).
const String riviumSyncSdkVersion = '0.2.6';
