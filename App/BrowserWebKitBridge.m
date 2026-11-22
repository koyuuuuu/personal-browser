#import "BrowserWebKitBridge.h"

void PBConfigureBackgroundAudio(WKWebView *view, WKFrameInfo *frame, BOOL enabled, BOOL foreground)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserBackgroundAudio?.configure(enabled, foreground);"
                   arguments:@{@"enabled": @(enabled), @"foreground": @(foreground)}
                     inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
void PBSetBackgroundAudioPolicy(WKWebView *view, BOOL enabled)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserBackgroundAudio?.policy(enabled);"
                   arguments:@{@"enabled": @(enabled)}
                     inFrame:nil inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
void PBArmBackgroundAudio(WKWebView *view, WKFrameInfo *frame, NSString *document, NSString *video, NSString *token)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserBackgroundAudio?.arm(documentID, video, token);"
                   arguments:@{@"documentID": document, @"video": video, @"token": token}
                     inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
void PBCommandBackgroundAudio(WKWebView *view, WKFrameInfo *frame, NSString *document, NSString *token, NSString *action)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserBackgroundAudio?.command(documentID, token, action);"
                   arguments:@{@"documentID": document, @"token": token, @"action": action}
                     inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
void PBStopBackgroundAudio(WKWebView *view, WKFrameInfo *frame)
{
    [view evaluateJavaScript:@"globalThis.__personalBrowserBackgroundAudio?.stop();"
                    inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}

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

void PBConfigureVideoOrientation(WKWebView *view, WKFrameInfo *frame, BOOL enabled, BOOL active)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserVideo?.configure(enabled, active);"
                   arguments:@{@"enabled": @(enabled), @"active": @(active)}
                     inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
void PBEnterVideoFullscreen(WKWebView *view, WKFrameInfo *frame, NSString *document, NSString *video)
{
    [view callAsyncJavaScript:@"globalThis.__personalBrowserVideo?.enter(document, video);"
                   arguments:@{@"document": document, @"video": video}
                     inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld completionHandler:nil];
}
