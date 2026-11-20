#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Botón flotante "R" sobre la partida, como RealModulesButton.java en Android: abre el menú de módulos de
// RealClient (Shift derecho) y, con un menú ya abierto, lo cierra (Esc). Se arrastra y recuerda su sitio.
@interface RPModulesButton : UIButton
+ (void)attachTo:(UIView *)view;
@end

NS_ASSUME_NONNULL_END
