#import "RPAccessViewController.h"
#import "RPSession.h"
#import "RPTheme.h"
#import "../LauncherSplitViewController.h"
#import "../UIKit+hook.h"

static NSString *const RPActivateTitle = @"Activar este iPhone";

@interface RPAccessViewController () <UITextFieldDelegate>
@property(nonatomic, copy, nullable) NSString *initialMessage;
@property(nonatomic) BOOL initialIsError;
@property(nonatomic) BOOL skipRestore;
@property(nonatomic) UIScrollView *scroll;
@property(nonatomic) UILabel *lead;
@property(nonatomic) UIStackView *fields;
@property(nonatomic) UIStackView *checking;
@property(nonatomic) UITextField *emailField;
@property(nonatomic) UITextField *codeField;
@property(nonatomic) UIButton *activateButton;
@property(nonatomic) UIActivityIndicatorView *buttonSpinner;
@property(nonatomic) UILabel *statusLabel;
@end

@implementation RPAccessViewController

#pragma mark - Entrada y salida

+ (void)presentGateWithMessage:(NSString *)message {
    [self presentGateWithMessage:message isError:YES];
}

+ (void)presentGateWithMessage:(NSString *)message isError:(BOOL)isError {
    RPAccessViewController *gate = [RPAccessViewController new];
    gate.initialMessage = message;
    gate.initialIsError = isError;
    gate.skipRestore = YES;
    [self swapRootOf:UIWindow.mainWindow to:gate];
}

+ (void)swapRootOf:(UIWindow *)window to:(UIViewController *)controller {
    if (!window) {
        return;
    }
    NSTimeInterval duration = UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.25;
    [UIView transitionWithView:window duration:duration options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
        window.rootViewController = controller;
    } completion:nil];
}

+ (void)confirmLogoutFrom:(UIViewController *)presenter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"¿Cerrar sesión de RealPhone?"
        message:@"Este iPhone deja de estar activado. Para volver a entrar necesitarás un código de invitación nuevo."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancelar" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cerrar sesión" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [RPSession.shared logout];
            dispatch_async(dispatch_get_main_queue(), ^{
                [RPAccessViewController presentGateWithMessage:@"Cerraste la sesión de RealPhone en este iPhone." isError:NO];
            });
        });
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)openLauncher {
    UIViewController *launcher = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
    [RPAccessViewController swapRootOf:self.view.window ?: UIWindow.mainWindow to:launcher];
}

#pragma mark - Vista

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    self.view.backgroundColor = RPBlack();
    [self buildLayout];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboardChanged:)
                                               name:UIKeyboardWillChangeFrameNotification object:nil];

    if (self.skipRestore) {
        [self showChecking:NO];
        [self showStatus:self.initialMessage isError:self.initialIsError];
        return;
    }
    [self showChecking:YES];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RPSessionState *state = [RPSession.shared restore];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (state.canPlay) {
                [self openLauncher];
                return;
            }
            self.emailField.text = state.email;
            [self showChecking:NO];
            [self showStatus:state.message isError:YES];
        });
    });
}

- (UIFont *)font:(CGFloat)size weight:(UIFontWeight)weight style:(UIFontTextStyle)style {
    return [[UIFontMetrics metricsForTextStyle:style] scaledFontForFont:[UIFont systemFontOfSize:size weight:weight]];
}

- (UIFont *)titleFont {
    UIFont *base = [UIFont systemFontOfSize:36 weight:UIFontWeightHeavy];
    UIFontDescriptor *rounded = [base.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
    UIFont *font = rounded ? [UIFont fontWithDescriptor:rounded size:36] : base;
    return [[UIFontMetrics metricsForTextStyle:UIFontTextStyleLargeTitle] scaledFontForFont:font];
}

- (UILabel *)label:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder name:(NSString *)name {
    UITextField *field = [UITextField new];
    field.font = [self font:17 weight:UIFontWeightRegular style:UIFontTextStyleBody];
    field.adjustsFontForContentSizeCategory = YES;
    field.textColor = RPText();
    field.tintColor = RPEmerald();
    field.backgroundColor = RPPanel();
    field.layer.cornerRadius = 12;
    field.layer.borderWidth = 1;
    field.layer.borderColor = RPStroke().CGColor;
    field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:placeholder
        attributes:@{NSForegroundColorAttributeName: RPTextFaint()}];
    field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)];
    field.leftViewMode = UITextFieldViewModeAlways;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.accessibilityLabel = name;
    field.delegate = self;
    [field.heightAnchor constraintGreaterThanOrEqualToConstant:50].active = YES;
    return field;
}

- (UIStackView *)buildStack {
    UIImageView *crown = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"RPCrown"]];
    crown.contentMode = UIViewContentModeScaleAspectFit;
    crown.translatesAutoresizingMaskIntoConstraints = NO;
    crown.isAccessibilityElement = NO;
    // El único acento de la pantalla: la corona brilla en esmeralda.
    crown.layer.shadowColor = RPEmerald().CGColor;
    crown.layer.shadowOpacity = 0.45;
    crown.layer.shadowRadius = 22;
    crown.layer.shadowOffset = CGSizeZero;
    UIView *crownRow = [UIView new];
    [crownRow addSubview:crown];
    [NSLayoutConstraint activateConstraints:@[
        [crown.leadingAnchor constraintEqualToAnchor:crownRow.leadingAnchor],
        [crown.topAnchor constraintEqualToAnchor:crownRow.topAnchor],
        [crown.bottomAnchor constraintEqualToAnchor:crownRow.bottomAnchor],
        [crown.widthAnchor constraintEqualToConstant:76],
        [crown.heightAnchor constraintEqualToConstant:58],
    ]];

    UILabel *title = [self label:@"RealPhone" font:[self titleFont] color:RPText()];
    title.accessibilityTraits = UIAccessibilityTraitHeader;
    self.lead = [self label:@"Activa este iPhone con la invitación que te dio NationCode. Solo se pide la primera vez."
                       font:[self font:17 weight:UIFontWeightRegular style:UIFontTextStyleBody] color:RPTextDim()];

    UIFont *caption = [self font:14 weight:UIFontWeightSemibold style:UIFontTextStyleSubheadline];
    UILabel *emailLabel = [self label:@"Correo" font:caption color:RPTextDim()];
    UILabel *codeLabel = [self label:@"Código de invitación" font:caption color:RPTextDim()];
    emailLabel.isAccessibilityElement = NO;
    codeLabel.isAccessibilityElement = NO;

    self.emailField = [self fieldWithPlaceholder:@"tu@correo.com" name:@"Correo"];
    self.emailField.keyboardType = UIKeyboardTypeEmailAddress;
    self.emailField.textContentType = UITextContentTypeEmailAddress;
    self.emailField.returnKeyType = UIReturnKeyNext;
    self.codeField = [self fieldWithPlaceholder:@"El que te envió NationCode" name:@"Código de invitación"];
    self.codeField.keyboardType = UIKeyboardTypeASCIICapable;
    self.codeField.returnKeyType = UIReturnKeyGo;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:RPActivateTitle forState:UIControlStateNormal];
    [button setTitleColor:RPOnEmerald() forState:UIControlStateNormal];
    [button setTitleColor:RPOnEmerald() forState:UIControlStateDisabled];
    button.titleLabel.font = [self font:17 weight:UIFontWeightSemibold style:UIFontTextStyleHeadline];
    button.titleLabel.adjustsFontForContentSizeCategory = YES;
    button.backgroundColor = RPEmerald();
    button.layer.cornerRadius = 12;
    [button.heightAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;
    [button addTarget:self action:@selector(activate) forControlEvents:UIControlEventTouchUpInside];
    self.activateButton = button;

    UIActivityIndicatorView *buttonSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    buttonSpinner.color = RPOnEmerald();
    buttonSpinner.hidesWhenStopped = YES;
    buttonSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    [button addSubview:buttonSpinner];
    [NSLayoutConstraint activateConstraints:@[
        [buttonSpinner.trailingAnchor constraintEqualToAnchor:button.trailingAnchor constant:-16],
        [buttonSpinner.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
    ]];
    self.buttonSpinner = buttonSpinner;

    self.statusLabel = [self label:nil font:[self font:15 weight:UIFontWeightRegular style:UIFontTextStyleCallout] color:RPDanger()];
    self.statusLabel.hidden = YES;
    UILabel *note = [self label:@"Cada código sirve una sola vez y para un solo dispositivo."
                           font:[self font:13 weight:UIFontWeightRegular style:UIFontTextStyleFootnote] color:RPTextFaint()];

    UIStackView *fields = [[UIStackView alloc] initWithArrangedSubviews:@[
        emailLabel, self.emailField, codeLabel, self.codeField, button, self.statusLabel, note,
    ]];
    fields.axis = UILayoutConstraintAxisVertical;
    fields.spacing = 8;
    [fields setCustomSpacing:18 afterView:self.emailField];
    [fields setCustomSpacing:24 afterView:self.codeField];
    [fields setCustomSpacing:14 afterView:button];
    [fields setCustomSpacing:14 afterView:self.statusLabel];
    self.fields = fields;

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.color = RPEmerald();
    [spinner startAnimating];
    UILabel *checkingLabel = [self label:@"Comprobando tu acceso…"
                                    font:[self font:17 weight:UIFontWeightRegular style:UIFontTextStyleBody] color:RPTextDim()];
    UIStackView *checking = [[UIStackView alloc] initWithArrangedSubviews:@[spinner, checkingLabel]];
    checking.axis = UILayoutConstraintAxisHorizontal;
    checking.alignment = UIStackViewAlignmentCenter;
    checking.spacing = 10;
    self.checking = checking;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[crownRow, title, self.lead, fields, checking]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 8;
    [stack setCustomSpacing:22 afterView:crownRow];
    [stack setCustomSpacing:10 afterView:title];
    [stack setCustomSpacing:32 afterView:self.lead];
    return stack;
}

- (void)buildLayout {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    scroll.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:scroll];
    self.scroll = scroll;

    UIView *content = [UIView new];
    content.translatesAutoresizingMaskIntoConstraints = NO;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(32, 24, 32, 24);
    [scroll addSubview:content];

    UIStackView *stack = [self buildStack];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:stack];

    UILayoutGuide *margins = content.layoutMarginsGuide;
    NSLayoutConstraint *fillWidth = [stack.widthAnchor constraintEqualToAnchor:margins.widthAnchor];
    fillWidth.priority = UILayoutPriorityDefaultHigh;
    NSLayoutConstraint *fillHeight = [content.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor];
    fillHeight.priority = UILayoutPriorityDefaultLow;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [content.heightAnchor constraintGreaterThanOrEqualToAnchor:scroll.frameLayoutGuide.heightAnchor],
        fillHeight,
        [stack.centerXAnchor constraintEqualToAnchor:content.centerXAnchor],
        [stack.centerYAnchor constraintEqualToAnchor:content.centerYAnchor],
        [stack.widthAnchor constraintLessThanOrEqualToConstant:400],
        [stack.leadingAnchor constraintGreaterThanOrEqualToAnchor:margins.leadingAnchor],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:margins.trailingAnchor],
        [stack.topAnchor constraintGreaterThanOrEqualToAnchor:margins.topAnchor],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:margins.bottomAnchor],
        fillWidth,
    ]];
}

#pragma mark - Estado

- (void)showChecking:(BOOL)checking {
    self.checking.hidden = !checking;
    self.fields.hidden = checking;
    self.lead.hidden = checking;
}

- (void)showStatus:(NSString *)text isError:(BOOL)isError {
    self.statusLabel.text = text;
    self.statusLabel.textColor = isError ? RPDanger() : RPTextDim();
    self.statusLabel.hidden = text.length == 0;
    if (text.length > 0) {
        UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, text);
    }
}

- (void)setBusy:(BOOL)busy {
    self.activateButton.enabled = !busy;
    self.activateButton.alpha = busy ? 0.7 : 1;
    [self.activateButton setTitle:busy ? @"Activando…" : RPActivateTitle forState:UIControlStateNormal];
    self.emailField.enabled = !busy;
    self.codeField.enabled = !busy;
    if (busy) {
        [self.buttonSpinner startAnimating];
    } else {
        [self.buttonSpinner stopAnimating];
    }
}

- (void)activate {
    [self.view endEditing:YES];
    NSString *email = self.emailField.text ?: @"";
    NSString *code = self.codeField.text ?: @"";
    [self setBusy:YES];
    [self showStatus:nil isError:NO];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        RPSessionState *state = [RPSession.shared activateEmail:email code:code];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self setBusy:NO];
            if (state.canPlay) {
                [self openLauncher];
            } else {
                [self showStatus:state.message ?: @"No se pudo activar este iPhone. Vuelve a intentarlo." isError:YES];
            }
        });
    });
}

#pragma mark - Teclado

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:end fromCoordinateSpace:UIScreen.mainScreen.coordinateSpace];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(local));
    UIEdgeInsets insets = UIEdgeInsetsMake(0, 0, overlap, 0);
    self.scroll.contentInset = insets;
    self.scroll.verticalScrollIndicatorInsets = insets;
    UIView *next = self.codeField.isFirstResponder ? (UIView *)self.activateButton
        : (self.emailField.isFirstResponder ? (UIView *)self.codeField : nil);
    if (next) {
        [self.scroll scrollRectToVisible:[next convertRect:next.bounds toView:self.scroll] animated:YES];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == self.emailField) {
        [self.codeField becomeFirstResponder];
    } else {
        [self activate];
    }
    return NO;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    textField.layer.borderColor = RPEmerald().CGColor;
    textField.layer.borderWidth = 1.5;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    textField.layer.borderColor = RPStroke().CGColor;
    textField.layer.borderWidth = 1;
}

@end
