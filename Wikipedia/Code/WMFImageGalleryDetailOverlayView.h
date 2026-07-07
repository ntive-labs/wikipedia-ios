@import UIKit;

@class MWKLicense;

@interface WMFImageGalleryDetailOverlayView : UIView
@property (nonatomic, copy) NSString *imageDescription;
@property (nonatomic, assign) BOOL imageDescriptionIsRTL;
@property (nonatomic, copy) dispatch_block_t ownerTapCallback;
@property (nonatomic, copy) dispatch_block_t infoTapCallback;
/// When set, an "Add caption" affordance is shown that invokes this block on tap.
@property (nonatomic, copy) dispatch_block_t captionEditTapCallback;
/// Accessible title shown alongside the caption-edit affordance (e.g. "Add caption").
@property (nonatomic, copy) NSString *captionEditButtonTitle;
@property (nonatomic, assign) CGFloat maximumDescriptionHeight;

- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

- (void)setLicense:(MWKLicense *)license owner:(NSString *)owner;

@end
