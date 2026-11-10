#import "BrowserWebKitBridge.h"

void PBRunPasswordCommand(WKWebView *view, WKFrameInfo *frame, NSDictionary<NSString *, id> *command,
                          void (^completion)(id _Nullable, NSError * _Nullable))
{
    [view callAsyncJavaScript:@"return globalThis.__personalBrowserPasswords?.command(command);"
                   arguments:@{@"command": command}
                     inFrame:frame
              inContentWorld:WKContentWorld.defaultClientWorld
           completionHandler:completion];
}

void PBSetPasswordSaveOffers(WKWebView *view, BOOL enabled)
{
    NSString *script = enabled ? @"globalThis.__personalBrowserPasswords?.setSaveOffers(true)"
                               : @"globalThis.__personalBrowserPasswords?.setSaveOffers(false)";
    [view evaluateJavaScript:script inFrame:nil inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}

void PBSetPasswordAppleHints(WKWebView *view, WKFrameInfo *frame, BOOL enabled)
{
    NSString *script = enabled ? @"globalThis.__personalBrowserPasswords?.setHints(true)"
                               : @"globalThis.__personalBrowserPasswords?.setHints(false)";
    [view evaluateJavaScript:script inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}

void PBApplyAppPromotionPolicy(WKWebView *view, BOOL enabled)
{
    NSString *script = enabled ? @"globalThis.__personalBrowserSetAppPromotions?.(true)"
                               : @"globalThis.__personalBrowserSetAppPromotions?.(false)";
    [view evaluateJavaScript:script inFrame:nil inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}

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
