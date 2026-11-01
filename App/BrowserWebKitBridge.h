#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
/// Calls the documented Objective-C API without the optional Swift overlay.
void PBApplyAudioMixingPolicy(WKWebView *view, BOOL enabled)
    NS_SWIFT_NAME(applyAudioMixingPolicy(_:enabled:));
/// JSON is produced by JSONSerialization, never interpolated from page text.
void PBRunAudioMixerCommand(WKWebView *view, WKFrameInfo *frame, NSString *json)
    NS_SWIFT_NAME(runAudioMixerCommand(_:frame:json:));
NS_ASSUME_NONNULL_END
