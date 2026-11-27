import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/app_storage.dart';
import 'alert_policy.dart';

/// What actually makes noise — replaced by a fake in tests.
abstract class AlertSink {
  Future<void> play(AlertKind kind, double volume);
}

/// Plays the bundled sounds. Best-effort: an audio failure (no device, unsupported platform) never reaches the UI.
/// The sound mixes with whatever the device is already playing instead of stopping it.
class PlayerAlertSink implements AlertSink {
  final AudioPlayer _player = AudioPlayer();
  bool _configured = false;

  static String _asset(AlertKind kind) => switch (kind) {
    AlertKind.ready => 'sounds/ready.wav',
    AlertKind.delayed => 'sounds/alert.wav',
    AlertKind.orderClosed => 'sounds/notification.mp3',
  };

  @override
  Future<void> play(AlertKind kind, double volume) async {
    try {
      if (!_configured) {
        _configured = true;
        try {
          await _player.setAudioContext(
            AudioContextConfig(
              focus: AudioContextConfigFocus.mixWithOthers,
            ).build(),
          );
        } catch (_) {
          /* not supported on this platform: default focus */
        }
      }
      await _player.stop();
      await _player.setVolume(volume.clamp(0.0, 1.0));
      await _player.play(AssetSource(_asset(kind)));
    } catch (_) {}
  }
}

final alertSinkProvider = Provider<AlertSink>((ref) => PlayerAlertSink());

/// The terminal's own sound preference (not an account setting: a phone in a pocket and a till do not want the same).
class SoundSettings {
  const SoundSettings({this.enabled = true, this.volume = 1.0});
  final bool enabled;
  final double volume;

  SoundSettings copyWith({bool? enabled, double? volume}) => SoundSettings(
    enabled: enabled ?? this.enabled,
    volume: volume ?? this.volume,
  );
}

class SoundSettingsNotifier extends Notifier<SoundSettings> {
  @override
  SoundSettings build() {
    final storage = ref.read(storageProvider);
    return SoundSettings(
      enabled: storage.alertSoundEnabled,
      volume: storage.alertSoundVolume,
    );
  }

  Future<void> setEnabled(bool value) async {
    state = state.copyWith(enabled: value);
    await ref
        .read(storageProvider)
        .setAlertSound(enabled: value, volume: state.volume);
  }

  Future<void> setVolume(double value) async {
    state = state.copyWith(volume: value.clamp(0.0, 1.0));
    await ref
        .read(storageProvider)
        .setAlertSound(enabled: state.enabled, volume: state.volume);
  }
}

final soundSettingsProvider =
    NotifierProvider<SoundSettingsNotifier, SoundSettings>(
      SoundSettingsNotifier.new,
    );
