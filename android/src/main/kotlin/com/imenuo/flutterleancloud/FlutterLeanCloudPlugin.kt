package com.imenuo.flutterleancloud

import com.avos.avoscloud.im.v2.AVIMClient
import com.avos.avoscloud.im.v2.AVIMMessageManager
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar


internal interface SubMethodCallHandler {
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean
}

internal interface ChannelEvent {
    data class Success(val event: Any) : ChannelEvent
    data class Error(val code: String, val message: String, val details: Any) : ChannelEvent
}

class FlutterLeanCloudPlugin(internal val registrar: Registrar) : MethodCallHandler, EventChannel.StreamHandler {
    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar): Unit {
            FlutterLeanCloudPlugin(registrar)
        }
    }

    internal val channel: MethodChannel = MethodChannel(registrar.messenger(),
            "flutter_leancloud")
    val eventChannel: EventChannel = EventChannel(registrar.messenger(),
            "flutter_leancloud/event")

    private val eventBuffer = mutableListOf<ChannelEvent>()
    private var eventSink : EventChannel.EventSink? = null

    private val handlers: List<SubMethodCallHandler> = listOf(
            AVIMClientMethodCallHandler(this),
            AVIMConversationMethodCallHandler(this)
    )

    init {
        channel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)

        AVIMMessageManager.setConversationEventHandler(ConversationEventHandler(this))
        AVIMClient.setClientEventHandler(ClientEventHandler(this))
    }

    override fun onMethodCall(call: MethodCall, result: Result): Unit {
        if (call.method == "_clearEventBuffer") {
            eventBuffer.clear()
            result.success(null)
            return
        }

        for (handler in handlers) {
            if (handler.onMethodCall(call, result))
                return
        }
        throw NotImplementedError("unhandled method ${call.method}")
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        val buffered = eventBuffer.toList()
        eventBuffer.clear()
        for (event in buffered) {
            sendEvent(event)
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    internal fun sendEvent(event: ChannelEvent) {
        val sink = eventSink
        if (sink == null) {
            eventBuffer.add(event)
        } else {
            when(event) {
                is ChannelEvent.Success -> sink.success(event.event)
                is ChannelEvent.Error -> sink.error(event.code, event.message, event.details)
            }
        }
    }
}
