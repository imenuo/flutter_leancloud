package com.imenuo.flutterleancloud

import com.avos.avoscloud.AVQuery
import com.avos.avoscloud.im.v2.*
import com.avos.avoscloud.im.v2.callback.AVIMConversationCallback
import com.avos.avoscloud.im.v2.callback.AVIMConversationQueryCallback
import com.avos.avoscloud.im.v2.callback.AVIMMessagesQueryCallback
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import timber.log.Timber


internal fun AVIMConversation.toFlutterMap(): Map<String, Any?> {
    val obj = HashMap<String, Any?>()
    obj["conversationId"] = this.conversationId
    obj["members"] = this.members
    obj["lastMessage"] = this.lastMessage?.toFlutterMap()
    obj["lastMessageAt"] = this.lastMessageAt?.time
    obj["unreadMessagesCount"] = this.unreadMessagesCount
    return obj
}

internal fun AVIMMessage.toFlutterMap(): Map<String, Any?> {
    val obj = HashMap<String, Any?>()
    obj["content"] = this.content
    obj["conversationId"] = this.conversationId
    obj["from"] = this.from
    obj["messageId"] = this.messageId
    obj["timestamp"] = this.timestamp
    obj["deliveredAt"] = this.deliveredAt
    obj["updateAt"] = this.updateAt
    obj["status"] = this.messageStatus.statusCode
    return obj
}

internal fun AVIMException.toFlutterMap(): Map<String, Any?> {
    val obj = HashMap<String, Any?>()
    obj["code"] = code
    obj["appCode"] = appCode
    obj["message"] = message
    return obj
}

internal fun parseCachePolicy(cachePolicy: Int?): AVQuery.CachePolicy? {
    return when (cachePolicy) {
        0 -> AVQuery.CachePolicy.CACHE_ELSE_NETWORK
        1 -> AVQuery.CachePolicy.CACHE_ONLY
        2 -> AVQuery.CachePolicy.CACHE_THEN_NETWORK
        3 -> AVQuery.CachePolicy.IGNORE_CACHE
        4 -> AVQuery.CachePolicy.NETWORK_ELSE_CACHE
        5 -> AVQuery.CachePolicy.NETWORK_ONLY
        else -> null
    }
}

internal class ClientEventHandler(private val plugin: FlutterLeanCloudPlugin) : AVIMClientEventHandler() {
    override fun onConnectionResume(client: AVIMClient) {
        this.plugin.sendEvent(ChannelEvent.Success(hashMapOf(
                "event" to "avIMClient_clientEventHandler_onConnectionResumed",
                "data" to hashMapOf(
                        "clientId" to client.clientId
                )
        )))
    }

    override fun onConnectionPaused(client: AVIMClient) {
        this.plugin.sendEvent(ChannelEvent.Success(hashMapOf(
                "event" to "avIMClient_clientEventHandler_onConnectionPaused",
                "data" to hashMapOf(
                        "clientId" to client.clientId
                )
        )))
    }

    override fun onClientOffline(client: AVIMClient, reason: Int) {}
}

internal class ConversationEventHandler(private val plugin: FlutterLeanCloudPlugin) : AVIMConversationEventHandler() {
    override fun onInvited(client: AVIMClient?, conversation: AVIMConversation?, p2: String?) {}

    override fun onMemberJoined(p0: AVIMClient?, p1: AVIMConversation?, p2: MutableList<String>?, p3: String?) {}

    override fun onKicked(client: AVIMClient, conversation: AVIMConversation, kickedBy: String?) {
        Timber.d("onKicked(${client.clientId}, ${conversation.conversationId}, $kickedBy)")

        this.plugin.sendEvent(ChannelEvent.Success(hashMapOf(
                "event" to "avIMClient_conversationEventHandler_onKicked",
                "data" to hashMapOf(
                        "clientId" to client.clientId,
                        "conversation" to conversation.toFlutterMap(),
                        "kickedBy" to kickedBy
                )
        )))
    }

    override fun onMemberLeft(p0: AVIMClient?, p1: AVIMConversation?, p2: MutableList<String>?, p3: String?) {}

    override fun onUnreadMessagesCountUpdated(client: AVIMClient, conversation: AVIMConversation) {
        super.onUnreadMessagesCountUpdated(client, conversation)

        this.plugin.sendEvent(ChannelEvent.Success(hashMapOf(
                "event" to "avIMClient_conversationEventHandler_onUnreadMessagesCountUpdated",
                "data" to hashMapOf(
                        "clientId" to client.clientId,
                        "conversation" to conversation.toFlutterMap()
                )
        )))
    }
}

private class MessageHandler(private val plugin: FlutterLeanCloudPlugin) : AVIMMessageHandler() {
    override fun onMessage(message: AVIMMessage, conversation: AVIMConversation, client: AVIMClient) {
        super.onMessage(message, conversation, client)

        this.plugin.sendEvent(ChannelEvent.Success(hashMapOf(
                "event" to "avIMClient_messageHandler_onMessage",
                "data" to hashMapOf(
                        "clientId" to client.clientId,
                        "message" to message.toFlutterMap(),
                        "conversation" to conversation.toFlutterMap()
                )
        )))
    }
}

internal class AVIMClientMethodCallHandler(private val plugin: FlutterLeanCloudPlugin) : SubMethodCallHandler {
    private var messageHandler: MessageHandler? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("avIMClient_"))
            return false

        val method = call.method.removePrefix("avIMClient_")
        when (method) {
            "registerMessageHandler" -> registerMessageHandler(result)
            "unregisterMessageHandler" -> unregisterMessageHandler(result)
            "getInstance" -> getInstance(call, result)
            "queryConversations" -> queryConversations(call, result)
            else -> throw NotImplementedError("unimplemented handler for: ${call.method}")
        }

        return true
    }

    private fun queryConversations(call: MethodCall, result: MethodChannel.Result) {
        val clientId: String = call.argument("clientId")!!
        val client = AVIMClient.getInstance(clientId)
        val ids: List<String> = call.argument("ids")!!
        // TODO 2018-08-19: isCompact not implemented in AVIMConversationsQuery, but documented in website
        // val isCompact: Boolean = call.argument("isCompact")
        val refreshLastMessage: Boolean = call.argument("refreshLastMessage")!!
        val cachePolicy: AVQuery.CachePolicy? = parseCachePolicy(call.argument("cachePolicy"))
        val limit: Int = call.argument("limit")!!

        val query = client.conversationsQuery
        query.limit(limit)
        query.whereContainsIn("objectId", ids)
        query.isWithLastMessagesRefreshed = refreshLastMessage
        if (cachePolicy != null) query.setQueryPolicy(cachePolicy)
        query.findInBackground(object : AVIMConversationQueryCallback() {
            override fun done(conversations: MutableList<AVIMConversation>?, exception: AVIMException?) {
                if (exception != null) {
                    Timber.e(exception, "cannot query conversations")
                    result.error("ERROR", "cannot query conversations", exception.toString())
                    return
                }
                if (conversations == null) {
                    result.error("ERROR", "assertion failed: conversation should not be null", null)
                    return
                }
                result.success(conversations.map { it.toFlutterMap() }.toMutableList())
            }
        })
    }

    private fun registerMessageHandler(result: MethodChannel.Result) {
        if (messageHandler != null) {
            result.success(null)
            return
        }
        messageHandler = MessageHandler(this.plugin)
        AVIMMessageManager.registerMessageHandler(AVIMMessage::class.java, messageHandler)
        result.success(null)
    }

    private fun unregisterMessageHandler(result: MethodChannel.Result) {
        if (messageHandler == null) {
            result.success(null)
            return
        }
        AVIMMessageManager.unregisterMessageHandler(AVIMMessage::class.java, messageHandler)
        messageHandler = null
        result.success(null)
    }

    private fun getInstance(call: MethodCall, result: MethodChannel.Result) {
        AVIMClient.getInstance(call.arguments as String)
        result.success(null)
    }
}

internal class AVIMConversationMethodCallHandler(private val plugin: FlutterLeanCloudPlugin) : SubMethodCallHandler {
    private fun internalGetConversation(clientId: String, conversationId: String): AVIMConversation {
        return AVIMClient.getInstance(clientId).getConversation(conversationId)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean {
        if (!call.method.startsWith("avIMConversation_"))
            return false

        val method = call.method.removePrefix("avIMConversation_")
        when (method) {
            "queryMessages" -> queryMessages(call, result)
            "sendMessage" -> sendMessage(call, result)
            "read" -> read(call, result)
            else -> throw NotImplementedError("unimplemented handler for ${call.method}")
        }

        return true
    }

    private fun sendMessage(call: MethodCall, result: MethodChannel.Result) {
        val clientId: String = call.argument("clientId")!!
        val conversationId: String = call.argument("conversationId")!!
        val content: String = call.argument("content")!!

        val conversation = internalGetConversation(clientId, conversationId)
        val message = AVIMMessage()
        message.content = content
        conversation.sendMessage(message, object : AVIMConversationCallback() {
            override fun done(exception: AVIMException?) {
                if (exception != null) {
                    val data = HashMap<String, Any?>()
                    data["message"] = message.toFlutterMap()
                    data["exception"] = exception.toFlutterMap()
                    result.error("ERROR", "send message failed", data)
                    return
                }
                result.success(message.toFlutterMap())
            }
        })
    }

    private fun queryMessages(call: MethodCall, result: MethodChannel.Result) {
        val clientId: String = call.argument("clientId")!!
        val conversationId: String = call.argument("conversationId")!!
        val msgId: String? = call.argument("msgId")
        val timestamp: Long? = call.argument("timestamp")
        val limit: Int = call.argument("limit")!!

        val conversation = internalGetConversation(clientId, conversationId)
        if (msgId == null || timestamp == null) {
            conversation.queryMessages(limit, MessagesQueryCallback(result))
        } else {
            conversation.queryMessages(msgId, timestamp, limit, MessagesQueryCallback(result))
        }
    }

    private fun read(call: MethodCall, result: MethodChannel.Result) {
        val clientId: String = call.argument("clientId")!!
        val conversationId: String = call.argument("conversationId")!!

        val conversation = internalGetConversation(clientId, conversationId)
        conversation.read()
        result.success(null)
    }

    class MessagesQueryCallback(private val result: MethodChannel.Result) : AVIMMessagesQueryCallback() {
        override fun done(msgs: MutableList<AVIMMessage>?, exception: AVIMException?) {
            if (exception != null) {
                result.error("ERROR", "cannot query messages", exception.toString())
                return
            }
            if (msgs == null) {
                result.error("ERROR", "assertion failed: msgs should not be null", null)
                return
            }
            result.success(msgs.map { it.toFlutterMap() }.toMutableList())
        }
    }
}
