#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Pantalla de acceso por invitación. Es la raíz de la ventana hasta que hay una sesión válida;
// entonces la cambia por el launcher.
@interface RPAccessViewController : UIViewController
// Vuelve a la pantalla de acceso desde cualquier parte (sesión revocada o vencida).
+ (void)presentGateWithMessage:(nullable NSString *)message;
+ (void)confirmLogoutFrom:(UIViewController *)presenter;
@end

NS_ASSUME_NONNULL_END
