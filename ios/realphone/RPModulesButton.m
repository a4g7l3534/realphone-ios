#import "RPModulesButton.h"
#import "RPTheme.h"
#include "../glfw_keycodes.h"
#include "../utils.h"

static NSString *const RPCenterKey = @"realphone.modules_button.center";
static const CGFloat RPButtonSize = 44;

@implementation RPModulesButton

+ (void)attachTo:(UIView *)view {
    RPModulesButton *button = [RPModulesButton buttonWithType:UIButtonTypeCustom];
    button.frame = CGRectMake(0, 0, RPButtonSize, RPButtonSize);
    button.layer.cornerRadius = RPButtonSize / 2;
    button.layer.borderWidth = 1.5;
    button.layer.borderColor = RPEmerald().CGColor;
    button.backgroundColor = [RPBlack() colorWithAlphaComponent:0.6];
    [button setTitle:@"R" forState:UIControlStateNormal];
    [button setTitleColor:RPText() forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    button.accessibilityLabel = @"Módulos de RealClient";
    button.accessibilityHint = @"Abre o cierra el menú de módulos. Arrástralo para moverlo.";
    button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [button addTarget:button action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:button action:@selector(drag:)]];
    [view addSubview:button];
    button.center = [button savedCenterIn:view.bounds.size];
}

- (CGPoint)fit:(CGPoint)point within:(CGSize)size {
    CGFloat margin = RPButtonSize / 2 + 6;
    return CGPointMake(MIN(MAX(point.x, margin), MAX(margin, size.width - margin)),
                       MIN(MAX(point.y, margin), MAX(margin, size.height - margin)));
}

- (CGPoint)savedCenterIn:(CGSize)size {
    NSString *saved = [NSUserDefaults.standardUserDefaults stringForKey:RPCenterKey];
    CGPoint unit = saved ? CGPointFromString(saved) : CGPointMake(0.93, 0.3);
    return [self fit:CGPointMake(unit.x * size.width, unit.y * size.height) within:size];
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *host = self.superview;
    CGPoint shift = [pan translationInView:host];
    self.center = [self fit:CGPointMake(self.center.x + shift.x, self.center.y + shift.y) within:host.bounds.size];
    [pan setTranslation:CGPointZero inView:host];
    CGSize size = host.bounds.size;
    if (pan.state == UIGestureRecognizerStateEnded && size.width > 0 && size.height > 0) {
        CGPoint unit = CGPointMake(self.center.x / size.width, self.center.y / size.height);
        [NSUserDefaults.standardUserDefaults setObject:NSStringFromCGPoint(unit) forKey:RPCenterKey];
    }
}

- (void)toggle {
    // Con el cursor capturado se está jugando y Shift derecho abre el menú; si no, hay un menú abierto y Esc lo cierra.
    int key = isGrabbing ? GLFW_KEY_RIGHT_SHIFT : GLFW_KEY_ESCAPE;
    CallbackBridge_nativeSendKey(key, 0, 1, 0);
    CallbackBridge_nativeSendKey(key, 0, 0, 0);
}

@end
