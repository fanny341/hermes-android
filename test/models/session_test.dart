import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:moritzu_hermes/core/models/session.dart';

void main() {
  group('Session.fromJson', () {
    test('parses complete session JSON', () {
      final json = jsonDecode('''
      {
        "id": "sess_123",
        "title": "Test Chat",
        "model": "hermes-agent",
        "source": "api",
        "message_count": 5,
        "started_at": 1700000000,
        "preview": "Hello, how can I help?",
        "ended_at": 1700003600,
        "is_running": false
      }
      ''') as Map<String, dynamic>;

      final session = Session.fromJson(json);

      expect(session.id, 'sess_123');
      expect(session.title, 'Test Chat');
      expect(session.model, 'hermes-agent');
      expect(session.source, 'api');
      expect(session.messageCount, 5);
      expect(session.isActive, false); // ended_at != null
      expect(session.isRunning, false);
      expect(session.preview, 'Hello, how can I help?');
      expect(session.startedAt, 1700000000);
      expect(session.endedAt, 1700003600);
    });

    test('parses active session without ended_at', () {
      final json = jsonDecode('''
      {
        "id": "sess_456",
        "title": "Active Chat",
        "model": "hermes-agent",
        "source": "api",
        "message_count": 3,
        "started_at": 1700000000,
        "preview": "",
        "is_running": true
      }
      ''') as Map<String, dynamic>;

      final session = Session.fromJson(json);

      expect(session.id, 'sess_456');
      expect(session.isActive, true);
      expect(session.isRunning, true);
      expect(session.endedAt, null);
    });

    test('handles missing fields gracefully', () {
      final session = Session.fromJson({});

      expect(session.id, '');
      expect(session.title, 'Untitled');
      expect(session.model, 'Default');
      expect(session.messageCount, 0);
      expect(session.isActive, true); // ended_at is null
      expect(session.isRunning, false);
      expect(session.preview, '');
      expect(session.startedAt, 0);
      expect(session.endedAt, null);
    });
  });
}
