#import "BrowserWebKitBridge.h"

void PBApplyAudioMixingPolicy(WKWebView *view, BOOL enabled)
{
    NSString *script = enabled ? @"globalThis.__personalBrowserSetAudioMixing?.(true)"
                               : @"globalThis.__personalBrowserSetAudioMixing?.(false)";
    [view evaluateJavaScript:script
                    inFrame:nil
             inContentWorld:WKContentWorld.defaultClientWorld
          completionHandler:nil];
}
