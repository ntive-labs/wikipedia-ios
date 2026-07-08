#import "WMFImageGalleryDetailOverlayView.h"
#import "WMFImageGalleryViewController.h"
#import "Wikipedia-Swift.h"
#import <WMF/WMF-Swift.h>
@import WMF.MWKLicense;

@interface WMFImageGalleryDetailOverlayView ()
@property (nonatomic, strong) IBOutlet WMFImageGalleryDescriptionTextView *imageDescriptionTextView; // Text view allows scrolling excess text.
@property (nonatomic, strong) IBOutlet UIButton *ownerButton;
@property (nonatomic, strong) IBOutlet UIButton *infoButton;
@property (nonatomic, strong) IBOutlet WMFLicenseView *ownerStackView;
@property (nonatomic, strong) IBOutlet UIImageView *lineImageView; // Retained to satisfy XIB outlet; no longer used.
@property (nonatomic, strong) UIButton *captionEditButton;
@property (nonatomic, strong) UIButton *tagsEditButton;

- (IBAction)didTapOwnerButton;
- (IBAction)didTapInfoButton;
- (IBAction)didTapDescriptionTextView;
- (IBAction)didTapBottomGradientView;

@end

@implementation WMFImageGalleryDetailOverlayView

- (void)setMaximumDescriptionHeight:(CGFloat)maximumDescriptionHeight {
    _maximumDescriptionHeight = maximumDescriptionHeight;
    self.imageDescriptionTextView.availableHeight = maximumDescriptionHeight;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    self.infoButton.imageView.contentMode = UIViewContentModeCenter;
    [self setupCaptionEditButton];
    [self setupTagsEditButton];
    [self wmf_configureSubviewsForDynamicType];
}

- (void)setupCaptionEditButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[WMFImageGalleryViewController captionEditButtonImage] forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    button.layer.cornerRadius = 16.0;
    button.clipsToBounds = YES;
    button.accessibilityLabel = WMFLocalizedStringWithDefaultValue(@"image-gallery-add-caption", nil, nil, @"Add caption", @"Accessibility label and title for the button that opens the Commons image caption editor.");
    [button addTarget:self action:@selector(didTapCaptionEditButton) forControlEvents:UIControlEventTouchUpInside];
    button.hidden = YES;
    [self addSubview:button];

    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16.0],
        [button.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
        [button.widthAnchor constraintEqualToConstant:32.0],
        [button.heightAnchor constraintEqualToConstant:32.0]
    ]];

    self.captionEditButton = button;
}

- (void)setCaptionEditTapCallback:(dispatch_block_t)captionEditTapCallback {
    _captionEditTapCallback = [captionEditTapCallback copy];
    self.captionEditButton.hidden = (captionEditTapCallback == nil);
}

- (void)setCaptionEditButtonTitle:(NSString *)captionEditButtonTitle {
    _captionEditButtonTitle = [captionEditButtonTitle copy];
    if (captionEditButtonTitle) {
        self.captionEditButton.accessibilityLabel = captionEditButtonTitle;
    }
}

- (void)didTapCaptionEditButton {
    if (self.captionEditTapCallback) {
        self.captionEditTapCallback();
    }
}

- (void)setupTagsEditButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setImage:[WMFImageGalleryViewController tagsEditButtonImage] forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.4];
    button.layer.cornerRadius = 16.0;
    button.clipsToBounds = YES;
    button.accessibilityLabel = WMFLocalizedStringWithDefaultValue(@"image-gallery-add-image-tags", nil, nil, @"Add image tags", @"Accessibility label and title for the button that opens the Commons image tags (depicts) editor.");
    [button addTarget:self action:@selector(didTapTagsEditButton) forControlEvents:UIControlEventTouchUpInside];
    button.hidden = YES;
    [self addSubview:button];

    // Positioned immediately to the leading side of the caption-edit button.
    [NSLayoutConstraint activateConstraints:@[
        [button.trailingAnchor constraintEqualToAnchor:self.captionEditButton.leadingAnchor constant:-8.0],
        [button.topAnchor constraintEqualToAnchor:self.topAnchor constant:8.0],
        [button.widthAnchor constraintEqualToConstant:32.0],
        [button.heightAnchor constraintEqualToConstant:32.0]
    ]];

    self.tagsEditButton = button;
}

- (void)setTagsEditTapCallback:(dispatch_block_t)tagsEditTapCallback {
    _tagsEditTapCallback = [tagsEditTapCallback copy];
    self.tagsEditButton.hidden = (tagsEditTapCallback == nil);
}

- (void)setTagsEditButtonTitle:(NSString *)tagsEditButtonTitle {
    _tagsEditButtonTitle = [tagsEditButtonTitle copy];
    if (tagsEditButtonTitle) {
        self.tagsEditButton.accessibilityLabel = tagsEditButtonTitle;
    }
}

- (void)didTapTagsEditButton {
    if (self.tagsEditTapCallback) {
        self.tagsEditTapCallback();
    }
}

- (IBAction)didTapOwnerButton {
    if (self.ownerTapCallback) {
        self.ownerTapCallback();
    }
}

- (IBAction)didTapInfoButton {
    if (self.infoTapCallback) {
        self.infoTapCallback();
    }
}

- (IBAction)didTapDescriptionTextView {}

- (IBAction)didTapBottomGradientView {}


- (NSString *)imageDescription {
    return self.imageDescriptionTextView.text;
}

- (void)setImageDescription:(NSString *)imageDescription {
    self.imageDescriptionTextView.text = imageDescription;
}

- (void)setImageDescriptionIsRTL:(BOOL)isRTL {
    self.imageDescriptionTextView.textAlignment = isRTL ? NSTextAlignmentRight : NSTextAlignmentLeft;
}

- (void)setLicense:(MWKLicense *)license owner:(NSString *)owner {
    NSString *code = [license.code lowercaseString];
    if (code) {
        NSArray<NSString *> *codes = [code componentsSeparatedByString:@"-"];
        self.ownerStackView.licenseCodes = codes;
    } else {
        self.ownerStackView.licenseCodes = @[@"generic"];
        if (license.shortDescription) {
            UILabel *licenseDescriptionLabel = [self newLicenseLabel];
            NSString *format = owner ? @"%@ \u2022 " : @"%@";
            licenseDescriptionLabel.text = [NSString stringWithFormat:format, license.shortDescription];
            [self.ownerStackView addArrangedSubview:licenseDescriptionLabel];
        }
    }

    if (!owner) {
        return;
    }

    UILabel *ownerLabel = [self newLicenseLabel];
    ownerLabel.text = owner;
    [self.ownerStackView addArrangedSubview:ownerLabel];
}

- (UILabel *)newLicenseLabel {
    UILabel *label = [[UILabel alloc] init];
    [label wmf_configureSubviewsForDynamicType];
    label.font = [WMFFontWrapper fontFor: WMFFontsSubheadline compatibleWithTraitCollection:self.traitCollection]; 
    label.textColor = [UIColor whiteColor];
    return label;
}

@end
