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
/// When set, an "Add image tags" affordance is shown that invokes this block on tap.
@property (nonatomic, copy) dispatch_block_t tagsEditTapCallback;
/// Accessible title shown alongside the tags-edit affordance (e.g. "Add image tags").
@property (nonatomic, copy) NSString *tagsEditButtonTitle;
@property (nonatomic, assign) CGFloat maximumDescriptionHeight;

- (instancetype)initWithFrame:(CGRect)frame NS_UNAVAILABLE;

- (void)setLicense:(MWKLicense *)license owner:(NSString *)owner;

@end
