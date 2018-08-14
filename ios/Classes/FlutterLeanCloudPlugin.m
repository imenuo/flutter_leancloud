#import "FlutterLeanCloudPlugin.h"
#import <flutter_leancloud/flutter_leancloud-Swift.h>

@implementation FlutterLeanCloudPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftFlutterLeanCloudPlugin registerWithRegistrar:registrar];
}
@end
