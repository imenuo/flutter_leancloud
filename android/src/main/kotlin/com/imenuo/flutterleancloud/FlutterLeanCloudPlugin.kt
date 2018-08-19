package com.imenuo.flutterleancloud

import com.avos.avoscloud.im.v2.AVIMClient
import com.avos.avoscloud.im.v2.AVIMMessageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar


internal interface SubMethodCallHandler {
    fun onMethodCall(call: MethodCall, result: MethodChannel.Result): Boolean
}

class FlutterLeanCloudPlugin(internal val registrar: Registrar) : MethodCallHandler {
    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar): Unit {
            FlutterLeanCloudPlugin(registrar)
        }
    }

    internal val channel: MethodChannel = MethodChannel(registrar.messenger(),
            "flutter_leancloud");
    private val handlers: List<SubMethodCallHandler> = listOf(
            AVIMClientMethodCallHandler(this),
            AVIMConversationMethodCallHandler(this)
    )

    init {
        channel.setMethodCallHandler(this)

        AVIMMessageManager.setConversationEventHandler(ConversationEventHandler(this))
        AVIMClient.setClientEventHandler(ClientEventHandler(this))
    }

    override fun onMethodCall(call: MethodCall, result: Result): Unit {
        for (handler in handlers) {
            if (handler.onMethodCall(call, result))
                return
        }
        throw NotImplementedError("unhandled method ${call.method}")
    }
}
