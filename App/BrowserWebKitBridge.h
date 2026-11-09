#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Secrets are passed as arguments, never embedded in JavaScript source.
void PBRunPasswordCommand(WKWebView *view, WKFrameInfo *frame, NSDictionary<NSString *, id> *command,
    void (^completion)(id _Nullable result, NSError * _Nullable error))
    NS_SWIFT_NAME(runPasswordCommand(_:frame:command:completion:));
void PBSetPasswordAppleHints(WKWebView *view, WKFrameInfo * _Nullable frame, BOOL enabled)
    NS_SWIFT_NAME(setPasswordAppleHints(_:frame:enabled:));
void PBApplyAppPromotionPolicy(WKWebView *view, BOOL enabled)
    NS_SWIFT_NAME(applyAppPromotionPolicy(_:enabled:));
/// Calls the documented Objective-C API without the optional Swift overlay.
void PBApplyAudioMixingPolicy(WKWebView *view, BOOL enabled)
    NS_SWIFT_NAME(applyAudioMixingPolicy(_:enabled:));
/// JSON is produced by JSONSerialization, never interpolated from page text.
void PBRunAudioMixerCommand(WKWebView *view, WKFrameInfo *frame, NSString *json)
    NS_SWIFT_NAME(runAudioMixerCommand(_:frame:json:));
NS_ASSUME_NONNULL_END
