import 'package:flutter/material.dart';

class HelpResponse {
  final int responderId;
  final String responderName;
  final String response; // 'on_way' | '5min' | 'cannot'

  const HelpResponse({
    required this.responderId,
    required this.responderName,
    required this.response,
  });

  factory HelpResponse.fromJson(Map<String, dynamic> j) => HelpResponse(
        responderId: j['responder_id'] as int,
        responderName: j['responder_name'] as String? ?? '?',
        response: j['response'] as String,
      );

  String get label => switch (response) {
        'on_way' => 'Auf dem Weg',
        '5min'   => '5 Minuten',
        'cannot' => 'Kann gerade nicht',
        _        => response,
      };

  Color get color => switch (response) {
        'on_way' => Colors.green,
        '5min'   => Colors.orange,
        'cannot' => Colors.red,
        _        => Colors.grey,
      };
}

class HelpRequest {
  final int id;
  final int requesterId;
  final String requesterName;
  final String? createdAt;
  final List<HelpResponse> responses;

  const HelpRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    this.createdAt,
    this.responses = const [],
  });

  factory HelpRequest.fromJson(Map<String, dynamic> j) => HelpRequest(
        id: j['id'] as int,
        requesterId: j['requester_id'] as int,
        requesterName: j['requester_name'] as String? ?? '?',
        createdAt: j['created_at'] as String?,
        responses: (j['responses'] as List? ?? [])
            .map((r) => HelpResponse.fromJson(r as Map<String, dynamic>))
            .toList(),
      );

  HelpRequest copyWith({List<HelpResponse>? responses}) => HelpRequest(
        id: id,
        requesterId: requesterId,
        requesterName: requesterName,
        createdAt: createdAt,
        responses: responses ?? this.responses,
      );

  /// True if someone is already on their way.
  bool get someoneOnWay => responses.any((r) => r.response == 'on_way');

  /// Highest-priority response to show the requester.
  HelpResponse? get primaryResponse {
    if (responses.isEmpty) return null;
    final onWay = responses.where((r) => r.response == 'on_way').firstOrNull;
    if (onWay != null) return onWay;
    final fiveMin = responses.where((r) => r.response == '5min').firstOrNull;
    if (fiveMin != null) return fiveMin;
    return responses.first;
  }
}
