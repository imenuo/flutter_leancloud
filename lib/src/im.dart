import 'dart:async';

import 'package:flutter/services.dart';

class AVIMClient {
  static const String _methodPrefix = 'avIMClient';
  static final Map<String, AVIMClient> _cache = {};
  final MethodChannel _channel;
  final String clientId;

  AVIMClient._init(this._channel, this.clientId);

  factory AVIMClient._internal(MethodChannel chanel, String clientId) {
    var client = _cache[clientId];
    if (client != null) return client;
    client = AVIMClient._init(chanel, clientId);
    _cache[clientId] = client;
    return client;
  }

  /// This should not be invoked directly,
  /// invoke `FlutterLeanCloud.avIMClientGetInstance()` instead.
  static Future<AVIMClient> getInstance(
      MethodChannel channel, String clientId) async {
    await channel.invokeMethod('${_methodPrefix}_getInstance', clientId);
    return AVIMClient._internal(channel, clientId);
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) =>
      _channel.invokeMethod('${_methodPrefix}_$method', arguments);

  Future<dynamic> onMethodCall(MethodCall methodCall) {}

  Future<void> open() async {
    await _invoke('open');
  }

  Future<void> registerMessageHandler(AVIMMessageHandler handler) async {}

  Future<List<AVIMConversation>> queryConversations(
    Iterable<String> conversationIds, {
    bool isCompat = true,
    bool refreshLastMessage = true,
  }) async {
    List<Map<String, dynamic>> maps = await _invoke('queryConversations', {
      'ids': conversationIds.toList(growable: false),
      'isCompat': isCompat,
      'refreshLastMessage': refreshLastMessage,
    });
    return maps.map((map) => AVIMConversation._fromMap(_channel, map)).toList();
  }

  Future<AVIMConversation> getConversation(
    String conversationId, {
    bool isCompat = true,
    bool refreshLastMessage = true,
  }) =>
      queryConversations(
        [conversationId],
        isCompat: isCompat,
        refreshLastMessage: refreshLastMessage,
      ).then((list) => list.first);
}

class Signature {
  final String signature;
  final int timestamp;
  final String nonce;
  final List<String> signedPeerIds;

  Signature({this.signature, this.timestamp, this.nonce, this.signedPeerIds});

  @override
  String toString() {
    return 'Signature{signature: $signature, timestamp: $timestamp, nonce: $nonce, signedPeerIds: $signedPeerIds}';
  }
}

abstract class SignatureFactory {
  Signature createSignature(String peerId, List<String> watchIds);
}

abstract class AVIMMessageHandler {
  void onMessage(AVIMMessage message, conversation, AVIMClient client);
}

abstract class AVIMClientEventHandler {
  // void onClientOffline(AVIMClient client, int code);
  void onConnectionPaused(AVIMClient client);
  void onConnectionResumed(AVIMClient client);
}

class AVIMConversation {
  static const String _methodPrefix = 'avIMConversation';

  final MethodChannel _channel;

  String conversationId;
  Set<String> members;
  AVIMMessage lastMessage;
  int lastMessageAt;
  int unreadMessagesCount;

  AVIMConversation._internal(this._channel);

  static AVIMConversation _fromMap(MethodChannel channel, Map map) {
    var conversation = AVIMConversation._internal(channel);
    conversation.conversationId = map['conversationId'];
    conversation.members = Set.of<String>(map['members']);
    conversation.lastMessage = AVIMMessage._fromMap(map['lastMessage']);
    conversation.lastMessageAt = map['lastMessageAt'];
    conversation.unreadMessagesCount = map['unreadMessagesCount'];
    return conversation;
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) =>
      _channel.invokeMethod('${_methodPrefix}_$method', arguments);

  Future<List<AVIMMessage>> queryMessages({
    String msgId,
    int timestamp,
    int limit = 50,
  }) async {
    List<Map> maps = await _invoke('queryMessages', {
      'msgId': msgId,
      'timestamp': timestamp,
      'limit': limit,
    });
    return maps.map(AVIMMessage._fromMap).toList();
  }

  Future<AVIMMessage> sendMessage(AVIMMessage message) async {
    Map map = await _invoke('sendMessage', message._toMap());
    return AVIMMessage._fromMap(map, message);
  }
}

class AVIMMessageStatus {
  final int statusCode;

  factory AVIMMessageStatus(int statusCode) {
    switch (statusCode) {
      case 0:
        return none;
      case 1:
        return sending;
      case 2:
        return sent;
      case 3:
        return receipt;
      case 4:
        return failed;
      case 5:
        return recalled;
      default:
        return null;
    }
  }

  const AVIMMessageStatus._internal(this.statusCode);

  @override
  String toString() {
    return 'AVIMMessageStatus{statusCode: $statusCode}';
  }

  static const none = AVIMMessageStatus._internal(0);
  static const sending = AVIMMessageStatus._internal(1);
  static const sent = AVIMMessageStatus._internal(2);
  static const receipt = AVIMMessageStatus._internal(3);
  static const failed = AVIMMessageStatus._internal(4);
  static const recalled = AVIMMessageStatus._internal(5);
}

class AVIMMessage {
  String content;
  String conversationId;
  String from;
  String messageId;
  int timestamp;
  int deliveredAt;
  int readAt;
  int updateAt;
  AVIMMessageStatus status;

  AVIMMessage() : status = AVIMMessageStatus.none;

  static AVIMMessage _fromMap(Map map, [AVIMMessage msg]) {
    if (msg == null) msg = AVIMMessage();
    msg.content = map['content'];
    msg.conversationId = map['conversationId'];
    msg.from = map['from'];
    msg.messageId = map['messageId'];
    msg.timestamp = map['timestamp'];
    msg.deliveredAt = map['deliveredAt'];
    msg.readAt = map['readAt'];
    msg.updateAt = map['updateAt'];
    msg.status = AVIMMessageStatus(map['status']);
    return msg;
  }

  Map<String, dynamic> _toMap() => {
        'content': content,
        'conversationId': conversationId,
        'from': from,
        'messageId': messageId,
        'timestamp': timestamp,
        'deliveredAt': deliveredAt,
        'readAt': readAt,
        'updateAt': updateAt,
        'status': status.statusCode,
      };
}
