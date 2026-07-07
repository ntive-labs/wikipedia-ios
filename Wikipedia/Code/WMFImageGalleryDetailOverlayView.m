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
