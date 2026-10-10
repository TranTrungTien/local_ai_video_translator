import 'package:flutter_test/flutter_test.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/media_session_snapshot.dart';
import 'package:local_ai_video_translator/features/player/domain/entities/player_state.dart';
import 'package:local_ai_video_translator/features/source_resolver/domain/entities/resolved_source.dart';

void main() {
  group('MediaSessionSnapshot Domain Tests', () {
    test('initial snapshot has idle status and zero durations', () {
      const snapshot = MediaSessionSnapshot.idle;
      expect(snapshot.status, equals(PlayerStatus.idle));
      expect(snapshot.position, equals(Duration.zero));
      expect(snapshot.duration, equals(Duration.zero));
      expect(snapshot.isPlaying, isFalse);
      expect(snapshot.isReady, isFalse);
      expect(snapshot.playbackRate, equals(1.0));
    });

    test('copyWith produces expected updated state', () {
      const snapshot = MediaSessionSnapshot.idle;
      final updated = snapshot.copyWith(
        status: PlayerStatus.playing,
        position: const Duration(seconds: 15),
        duration: const Duration(minutes: 10),
        playbackRate: 1.25,
      );

      expect(updated.status, equals(PlayerStatus.playing));
      expect(updated.isPlaying, isTrue);
      expect(updated.isReady, isTrue);
      expect(updated.position, equals(const Duration(seconds: 15)));
      expect(updated.playbackRate, equals(1.25));
    });

    test('isolates request context between media sessions', () {
      const contextA = RequestContext(
        userAgent: 'AgentA/1.0',
        headers: {'Authorization': 'Bearer TokenA'},
      );
      const contextB = RequestContext(
        userAgent: 'AgentB/2.0',
        headers: {'Authorization': 'Bearer TokenB'},
      );

      final snapshotA = MediaSessionSnapshot.idle.copyWith(
        requestContext: contextA,
      );
      final snapshotB = MediaSessionSnapshot.idle.copyWith(
        requestContext: contextB,
      );

      expect(
        snapshotA.requestContext.headers['Authorization'],
        equals('Bearer TokenA'),
      );
      expect(
        snapshotB.requestContext.headers['Authorization'],
        equals('Bearer TokenB'),
      );
      expect(
        snapshotA.requestContext.headers['Authorization'],
        isNot(equals(snapshotB.requestContext.headers['Authorization'])),
      );
    });
  });
}
