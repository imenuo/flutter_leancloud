import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class AVIMClient {
  static final Map<String, AVIMClient> _cache = {};
  final Logger _logger;
  final MethodChannel _channel;
  final String clientId;
  AVIMMessageHandler messageHandler;
  AVIMClientEventHandler clientEventHandler;
  AVIMConversationEventHandler conversationEventHandler;

  AVIMClient._init(this._channel, this.clientId)
      : _logger = new Logger('AVIMClient($clientId)');

  factory AVIMClient._internal(MethodChannel chanel, String clientId) {
    var client = _cache[clientId];
    if (client != null) return client;
    client = AVIMClient._init(chanel, clientId);
    _cache[clientId] = client;
    return client;
  }

  factory AVIMClient._fromCache(String clientId) => _cache[clientId];

  /// This should not be invoked directly,
  /// invoke `FlutterLeanCloud.avIMClientGetInstance()` instead.
  static Future<AVIMClient> getInstance(
      MethodChannel channel, String clientId) async {
    if (_cache.containsKey(clientId)) return _cache[clientId];
    await channel.invokeMethod('avIMClient_getInstance', clientId);
    return AVIMClient._internal(channel, clientId);
  }

  static Future<void> registerMessageHandler(MethodChannel channel) async {
    await channel.invokeMethod('avIMClient_registerMessageHandler');
  }

  static Future<void> unregisterMessageHandler(MethodChannel channel) async {
    await channel.invokeMethod('avIMClient_unregisterMessageHandler');
  }

  static Future<void> handleMessageHandlerOnMessage(Map arguments) async {
    final String clientId = arguments['clientId'];
    final client = AVIMClient._fromCache(clientId);
    if (client == null) return;
    client._handleMessageHandlerOnMessage(arguments);
  }

  void close() {
    clientEventHandler = null;
    conversationEventHandler = null;
    messageHandler = null;
    AVIMConversation._evictCache();
    _cache.remove(clientId);
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) {
    final nativeMethod = 'avIMClient_$method';
    _logger.finest('_invoke($nativeMethod, $arguments)');
    return _channel.invokeMethod(nativeMethod, arguments);
  }

  Future<List<AVIMConversation>> queryConversations(
    Iterable<String> conversationIds, {
    bool isCompact = true,
    bool refreshLastMessage = true,
    AVQueryCachePolicy cachePolicy,
    limit = 10,
  }) async {
    List maps = await _invoke('queryConversations', {
      'clientId': clientId,
      'ids': conversationIds.toList(growable: false),
      'isCompact': isCompact,
      'refreshLastMessage': refreshLastMessage,
      'cachePolicy': cachePolicy?.cachePolicy,
      'limit': limit,
    });
    return maps
        .cast<Map>()
        .map((map) => AVIMConversation._fromMap(_channel, map, clientId))
        .toList();
  }

  Future<AVIMConversation> getConversation(
    String conversationId, {
    bool isCompact = true,
    bool refreshLastMessage = true,
    AVQueryCachePolicy cachePolicy,
  }) =>
      queryConversations(
        [conversationId],
        isCompact: isCompact,
        refreshLastMessage: refreshLastMessage,
        cachePolicy: cachePolicy,
      ).then((list) => list.isEmpty ? null : list.first);

  Future<dynamic> onClientMethodCall(MethodCall methodCall) {
    final method = methodCall.method;
    final args = methodCall.arguments;
    switch (method) {
      case 'avIMClient_clientEventHandler_onConnectionPaused':
        return _handleClientEventHandlerOnConnectionPaused(args);
      case 'avIMClient_clientEventHandler_onConnectionResumed':
        return _handleClientEventHandlerOnConnectionResumed(args);
      case 'avIMClient_conversationEventHandler_onUnreadMessagesCountUpdated':
        return _handleConversationEventHandlerOnUnreadMessagesCountUpdated(
            args);
      case 'avIMClient_conversationEventHandler_onKicked':
        return _handleConversationEventHandlerOnKicked(args);
      default:
        _logger.shout('unhandled method call: $methodCall');
    }
  }

  Future<void> _handleMessageHandlerOnMessage(Map arguments) async {
    await messageHandler?.onMessage(
        AVIMMessage._fromMap(arguments['message']),
        AVIMConversation._fromMap(
            _channel, arguments['conversation'], clientId),
        this);
  }

  Future<void> _handleClientEventHandlerOnConnectionPaused(arguments) async {
    await clientEventHandler?.onConnectionPaused(this);
  }

  Future<void> _handleClientEventHandlerOnConnectionResumed(args) async {
    await clientEventHandler?.onConnectionResumed(this);
  }

  Future<void> _handleConversationEventHandlerOnUnreadMessagesCountUpdated(
      args) async {
    await conversationEventHandler?.onUnreadMessagesCountUpdated(this,
        AVIMConversation._fromMap(_channel, args['conversation'], clientId));
  }

  Future<void> _handleConversationEventHandlerOnKicked(args) async {
    await conversationEventHandler?.onKicked(
        this,
        AVIMConversation._fromMap(_channel, args['conversation'], clientId),
        args['kickedBy']);
  }
}

abstract class AVIMMessageHandler {
  FutureOr<void> onMessage(
      AVIMMessage message, AVIMConversation conversation, AVIMClient client);
}

abstract class AVIMConversationEventHandler {
  FutureOr<void> onUnreadMessagesCountUpdated(
      AVIMClient client, AVIMConversation conversation);

  FutureOr<void> onKicked(
      AVIMClient client, AVIMConversation conversation, String kickedBy);
}

abstract class AVIMClientEventHandler {
  // void onClientOffline(AVIMClient client, int code);
  FutureOr<void> onConnectionPaused(AVIMClient client);

  FutureOr<void> onConnectionResumed(AVIMClient client);
}

class AVQueryCachePolicy {
  final int cachePolicy;

  const AVQueryCachePolicy._internal(this.cachePolicy);

  factory AVQueryCachePolicy(int cachePolicy) {
    switch (cachePolicy) {
      case 0:
        return CACHE_ELSE_NETWORK;
      case 1:
        return CACHE_ONLY;
      case 2:
        return CACHE_THEN_NETWORK;
      case 3:
        return IGNORE_CACHE;
      case 4:
        return NETWORK_ELSE_CACHE;
      case 5:
        return NETWORK_ONLY;
      default:
        return null;
    }
  }

  static const CACHE_ELSE_NETWORK = AVQueryCachePolicy._internal(0);
  static const CACHE_ONLY = AVQueryCachePolicy._internal(1);
  static const CACHE_THEN_NETWORK = AVQueryCachePolicy._internal(2);
  static const IGNORE_CACHE = AVQueryCachePolicy._internal(3);
  static const NETWORK_ELSE_CACHE = AVQueryCachePolicy._internal(4);
  static const NETWORK_ONLY = AVQueryCachePolicy._internal(5);
}

class AVIMException {
  final int code;
  final int appCode;
  final String message;

  AVIMException._internal({this.code, this.appCode, this.message});

  @override
  String toString() {
    return 'AVIMException{code: $code, appCode: $appCode, message: $message}';
  }

  static AVIMException _fromMap(Map map) => new AVIMException._internal(
        code: map['code'],
        appCode: map['appCode'],
        message: map['message'],
      );
}

class AVIMConversation {
  static final _cache = <String, AVIMConversation>{};

  final Logger _logger;
  final MethodChannel _channel;
  final String conversationId;
  final String clientId;

  Set<String> members;
  AVIMMessage lastMessage;
  int lastMessageAt;
  int unreadMessagesCount;

  AVIMConversation._init(this._channel, this.conversationId, this.clientId)
      : _logger = new Logger('AVIMConversation($conversationId)');

  factory AVIMConversation._internal(
      MethodChannel channel, String conversationId, String clientId) {
    var conversation = _cache[conversationId];
    if (conversation != null) return conversation;

    conversation =
        new AVIMConversation._init(channel, conversationId, clientId);
    _cache[conversationId] = conversation;
    return conversation;
  }

  static AVIMConversation _fromCache(String conversationId) =>
      _cache[conversationId];

  static void _evictCache() {
    _cache.clear();
  }

  static String _parseConversationId(Map map) => map['conversationId'];

  static AVIMConversation _fromMap(
      MethodChannel channel, Map map, String clientId) {
    var conversation =
        AVIMConversation._internal(channel, map['conversationId'], clientId);
    conversation.members = Set.of((map['members'] as List).cast<String>());
    conversation.lastMessage = map['lastMessage'] == null
        ? null
        : AVIMMessage._fromMap(map['lastMessage']);
    conversation.lastMessageAt = map['lastMessageAt'];
    conversation.unreadMessagesCount = map['unreadMessagesCount'];
    return conversation;
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) {
    final nativeMethod = 'avIMConversation_$method';
    _logger.finest('_invoke($nativeMethod, $arguments)');
    return _channel.invokeMethod(nativeMethod, arguments);
  }

  Future<List<AVIMMessage>> queryMessages({
    String msgId,
    int timestamp,
    int limit = 50,
  }) async {
    assert(limit != null);
    List maps = await _invoke('queryMessages', {
      'clientId': clientId,
      'conversationId': conversationId,
      'msgId': msgId,
      'timestamp': timestamp,
      'limit': limit,
    });
    return maps.cast<Map>().map(AVIMMessage._fromMap).toList();
  }

  Future<AVIMMessage> sendMessage(AVIMMessage message) async {
    message.conversationId = conversationId;

    try {
      Map map = await _invoke('sendMessage', {
        'clientId': clientId,
        'conversationId': conversationId,
        'content': message.content,
      });
      return AVIMMessage._fromMap(map, message);
    } on PlatformException catch (e) {
      final details = e.details as Map;
      AVIMMessage._fromMap(details['message'], message);
      throw AVIMException._fromMap(details['exception']);
    }
  }

  Future<void> read() async {
    await _invoke('read', {
      'clientId': clientId,
      'conversationId': conversationId,
    });
  }

  @override
  String toString() {
    return 'AVIMConversation{_channel: $_channel, conversationId: $conversationId, clientId: $clientId, members: $members, lastMessage: $lastMessage, lastMessageAt: $lastMessageAt, unreadMessagesCount: $unreadMessagesCount}';
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
        'updateAt': updateAt,
        'status': status.statusCode,
      };

  @override
  String toString() {
    return 'AVIMMessage{content: $content, conversationId: $conversationId, from: $from, messageId: $messageId, timestamp: $timestamp, deliveredAt: $deliveredAt, updateAt: $updateAt, status: $status}';
  }
}
