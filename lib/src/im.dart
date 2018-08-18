import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

class AVIMClient {
  static final Map<String, AVIMClient> _cache = {};
  final Logger _logger;
  final MethodChannel _channel;
  final String clientId;
  SignatureFactory signatureFactory;
  AVIMMessageHandler _messageHandler;
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

  /// This should not be invoked directly,
  /// invoke `FlutterLeanCloud.avIMClientGetInstance()` instead.
  static Future<AVIMClient> getInstance(
      MethodChannel channel, String clientId) async {
    await channel.invokeMethod('avIMClient_getInstance', clientId);
    return AVIMClient._internal(channel, clientId);
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) =>
      _channel.invokeMethod('avIMClient_$method', arguments);

  Future<void> open() async {
    await _invoke('open', clientId);
  }

  Future<void> registerMessageHandler(AVIMMessageHandler handler) async {
    _messageHandler = handler;
    await _invoke('registerMessageHandler', clientId);
  }

  Future<void> unregisterMessageHandler() async {
    await _invoke('unregisterMessageHandler', clientId);
    _messageHandler = null;
  }

  Future<List<AVIMConversation>> queryConversations(
    Iterable<String> conversationIds, {
    bool isCompat = true,
    bool refreshLastMessage = true,
  }) async {
    List<Map> maps = await _invoke('queryConversations', {
      'clientId': clientId,
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

  Future<dynamic> onClientMethodCall(MethodCall methodCall) {
    final method = methodCall.method;
    final args = methodCall.arguments;
    switch (method) {
      case 'avIMClient_signatureFactory_createSignature':
        return _handleSignatureFactoryCreateSignature(args);
      case 'avIMClient_messageHandler_onMessage':
        return _handleMessageHandlerOnMessage(args);
      case 'avIMClient_clientEventHandler_onConnectionPaused':
        return _handleClientEventHandlerOnConnectionPaused(args);
      case 'avIMClient_clientEventHandler_onConnectionResumed':
        return _handleClientEventHandlerOnConnectionResumed(args);
      case 'avIMClient_conversationEventHandler_onUnreadMessagesCountUpdated':
        return _handleConversationEventHandlerOnUnreadMessagesCountUpdated(
            args);
      default:
        _logger.shout('unhandled method call: $methodCall');
    }
  }

  Future<Map> _handleSignatureFactoryCreateSignature(Map arguments) async {
    if (this.signatureFactory == null) {
      _logger.warning('missing signatureFactory');
      throw PlatformException(
        code: 'UNSET',
        message: 'signatureFactory is not set',
      );
    }

    var signature = await this
        .signatureFactory
        .createSignature(arguments['peerId'], arguments['watchIds']);

    return signature._toMap();
  }

  Future<void> _handleMessageHandlerOnMessage(Map arguments) async {
    await _messageHandler?.onMessage(AVIMMessage._fromMap(arguments['message']),
        AVIMConversation._fromMap(_channel, arguments['conversation']), this);
  }

  Future<void> _handleClientEventHandlerOnConnectionPaused(arguments) async {
    await clientEventHandler?.onConnectionPaused(this);
  }

  Future<void> _handleClientEventHandlerOnConnectionResumed(args) async {
    await clientEventHandler?.onConnectionResumed(this);
  }

  Future<void> _handleConversationEventHandlerOnUnreadMessagesCountUpdated(
      args) async {
    await conversationEventHandler?.onUnreadMessagesCountUpdated(
        this, AVIMConversation._fromMap(_channel, args['conversation']));
  }
}

class Signature {
  final String signature;
  final int timestamp;
  final String nonce;
  final List<String> signedPeerIds;

  Signature({this.signature, this.timestamp, this.nonce, this.signedPeerIds});

  Map _toMap() => {
        'signature': this.signature,
        'timestamp': this.timestamp,
        'nonce': this.nonce,
        'signedPeerIds': this.signedPeerIds,
      };

  @override
  String toString() {
    return 'Signature{signature: $signature, timestamp: $timestamp, nonce: $nonce, signedPeerIds: $signedPeerIds}';
  }
}

abstract class SignatureFactory {
  FutureOr<Signature> createSignature(String peerId, List<String> watchIds);
}

abstract class AVIMMessageHandler {
  FutureOr<void> onMessage(
      AVIMMessage message, AVIMConversation conversation, AVIMClient client);
}

abstract class AVIMConversationEventHandler {
  FutureOr<void> onUnreadMessagesCountUpdated(
      AVIMClient client, AVIMConversation conversation);
}

abstract class AVIMClientEventHandler {
  // void onClientOffline(AVIMClient client, int code);
  FutureOr<void> onConnectionPaused(AVIMClient client);
  FutureOr<void> onConnectionResumed(AVIMClient client);
}

class AVIMConversation {
  static final _cache = <String, AVIMConversation>{};

  final MethodChannel _channel;
  final String conversationId;

  Set<String> members;
  AVIMMessage lastMessage;
  int lastMessageAt;
  int unreadMessagesCount;

  AVIMConversation._init(this._channel, this.conversationId);

  factory AVIMConversation._internal(
      MethodChannel channel, String conversationId) {
    var conversation = _cache[conversationId];
    if (conversation != null) return conversation;

    conversation = new AVIMConversation._init(channel, conversationId);
    _cache[conversationId] = conversation;
    return conversation;
  }

  static AVIMConversation _fromCache(String conversationId) =>
      _cache[conversationId];

  static AVIMConversation _fromMap(MethodChannel channel, Map map) {
    var conversation =
        AVIMConversation._internal(channel, map['conversationId']);
    conversation.members = Set.of<String>(map['members']);
    conversation.lastMessage = AVIMMessage._fromMap(map['lastMessage']);
    conversation.lastMessageAt = map['lastMessageAt'];
    conversation.unreadMessagesCount = map['unreadMessagesCount'];
    return conversation;
  }

  Future<dynamic> _invoke(String method, [dynamic arguments]) =>
      _channel.invokeMethod('avIMConversation_$method', arguments);

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
