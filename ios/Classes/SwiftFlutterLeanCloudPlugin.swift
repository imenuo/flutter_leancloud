import Flutter
import UIKit

protocol SubMethodCallHandler {
    func onMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) -> Bool
}

public class SwiftFlutterLeanCloudPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_leancloud", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterLeanCloudPlugin(with: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public let channel: FlutterMethodChannel
    private var handlers: [SubMethodCallHandler] = []

    init(with channel: FlutterMethodChannel) {
        self.channel = channel
        
        super.init()
        
        self.handlers.append(AVIMClientMethodCallHandler(with: self))
        self.handlers.append(AVIMConversationMethodCallHandler())
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        for handler in handlers {
            if handler.onMethodCall(call, result: result) {
                return
            }
        }
        result(FlutterMethodNotImplemented)
    }
}
