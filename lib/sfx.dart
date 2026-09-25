import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'game.dart';

/// Background music arrangements: the menus and the city play the same song differently.
enum Music {
  menu('menu'),
  game('cozy');

  const Music(this.file);
  final String file;
}

/// Plays the game's sound effects and background music with SoLoud (low latency, many
/// sounds at once). Stays silent until [init] succeeds, so tests and machines without audio
/// just run quietly. On/off and volumes come from Settings via [configure].
class Sounds {
  static final _sources = <Sfx, AudioSource>{};
  static final _clock = Stopwatch()..start();
  static final _lastPlayed = <Sfx, int>{};
  static final _tracks = <Music, SoundHandle>{};
  static Music _scene = Music.menu;
  static bool sfxOn = true, musicOn = true;
  static double sfxVolume = 1, musicVolume = .35;
  static const _fade = Duration(milliseconds: 900);

  static bool get ready => _sources.length == Sfx.values.length && _tracks.length == Music.values.length;
  static SoundHandle? get _music => _tracks[_scene];

  static Future<void> init() async {
    try {
      await SoLoud.instance.init();
      for (final s in Sfx.values) {
        _sources[s] = await SoLoud.instance.loadAsset('assets/sfx/${s.name}.wav');
      }
      // Cozy SNES-style loops (tool/gen_music.py), quietly under the effects: one song,
      // arranged once for the menus and once for the city. Only the current one plays.
      for (final m in Music.values) {
        final src = await SoLoud.instance.loadAsset('assets/music/${m.file}.ogg');
        _tracks[m] = SoLoud.instance.play(src, looping: true, volume: musicVolume, paused: !musicOn || m != _scene);
      }
    } catch (e) {
      debugPrint('Sound off: $e');
    }
  }

  /// Cross-fades to [m]'s arrangement (menus ↔ city).
  static void scene(Music m) {
    if (m == _scene) return;
    final old = _music;
    _scene = m;
    final now = _music;
    if (old == null || now == null) return;
    SoLoud.instance.fadeVolume(old, 0, _fade);
    SoLoud.instance.schedulePause(old, _fade);
    if (!musicOn) return;
    SoLoud.instance.setVolume(now, 0);
    SoLoud.instance.setPause(now, false);
    SoLoud.instance.fadeVolume(now, musicVolume, _fade);
  }

  static void configure({required bool sfx, required double sfxVol, required bool music, required double musicVol}) {
    sfxOn = sfx;
    sfxVolume = sfxVol;
    musicOn = music;
    musicVolume = musicVol;
    if (_music case final h?) {
      SoLoud.instance.setVolume(h, musicVolume);
      SoLoud.instance.setPause(h, !musicOn);
    }
  }

  // Fares ring constantly at 3x speed: keep them quiet and spaced out.
  static const _volume = {Sfx.deliver: .25, Sfx.station: .5, Sfx.leave: .45};
  static const _gapMs = {Sfx.deliver: 120, Sfx.leave: 250};

  static void play(Sfx s) {
    final src = _sources[s];
    if (!sfxOn || src == null) return;
    final now = _clock.elapsedMilliseconds;
    if (now - (_lastPlayed[s] ?? -1 << 30) < (_gapMs[s] ?? 60)) return;
    _lastPlayed[s] = now;
    SoLoud.instance.play(src, volume: (_volume[s] ?? .7) * sfxVolume);
  }
}
