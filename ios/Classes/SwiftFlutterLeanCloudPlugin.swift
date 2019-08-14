import Flutter
import UIKit
import AVOSCloudIM

protocol SubMethodCallHandler {
    func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool
}

public protocol ChannelEvent {
}

public class ChannelEventSuccess: ChannelEvent {
    public let event: Any?
    init(withEvent event: Any?) {
        self.event = event
    }
}

public class ChannelEventError: ChannelEvent {
    public let code: String
    public let message: String
    public let details: Any?
    init(with code: String, message: String, details: Any?) {
        self.code = code
        self.message = message
        self.details = details
    }
}

public class SwiftFlutterLeanCloudPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_leancloud", binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(name: "flutter_leancloud/event", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterLeanCloudPlugin(with: channel, eventChannel: eventChannel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public let channel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var handlers: [SubMethodCallHandler] = []
    
    private var eventBuffer: [ChannelEvent] = []
    private var eventSink: FlutterEventSink? = nil

    public static func getAVIMClient(clientId: String) -> AVIMClient {
        return AVIMClientMethodCallHandler.getClient(clientId: clientId)
    }
  
    init(with channel: FlutterMethodChannel, eventChannel: FlutterEventChannel) {
        self.channel = channel
        self.eventChannel = eventChannel
        
        super.init()
        
        self.eventChannel.setStreamHandler(self)
        self.handlers.append(AVIMClientMethodCallHandler(with: self))
        self.handlers.append(AVIMConversationMethodCallHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "_clearEventBuffer" {
            self.eventBuffer = []
            result(nil)
            return
        }
        
        for handler in handlers {
            if handler.onMethodCall(call, result: result) {
                return
            }
        }
        result(FlutterMethodNotImplemented)
    }
    
    public func sendEvent(_ event: ChannelEvent) {
        if let sink = eventSink {
            switch(event) {
            case is ChannelEventSuccess:
                sink((event as! ChannelEventSuccess).event)
            case is ChannelEventError:
                let ev = event as! ChannelEventError
                sink(FlutterError(code: ev.code, message: ev.message, details: ev.details))
            default:
                return
            }
        } else {
            eventBuffer.append(event)
        }
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        let events = eventBuffer
        self.eventBuffer = []
        for event in events {
            sendEvent(event)
        }
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }
}
