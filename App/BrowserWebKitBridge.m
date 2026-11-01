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

void PBRunAudioMixerCommand(WKWebView *view, WKFrameInfo *frame, NSString *json)
{
    NSString *script = [NSString stringWithFormat:@"void globalThis.__personalBrowserMixer?.command(%@)", json];
    [view evaluateJavaScript:script
                    inFrame:frame
             inContentWorld:WKContentWorld.defaultClientWorld
          completionHandler:nil];
}
