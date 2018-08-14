#import "FlutterLeancloudPlugin.h"
#import <flutter_leancloud/flutter_leancloud-Swift.h>

@implementation FlutterLeancloudPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterLeancloudPlugin registerWithRegistrar:registrar];
}
@end
