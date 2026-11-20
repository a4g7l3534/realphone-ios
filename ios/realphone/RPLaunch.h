#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Une RealPhone con el launcher de Amethyst: perfiles "RealClient <versión>" en launcher_profiles.json y la
// preparación antes de que el motor descargue y arranque el juego.
@interface RPLaunch : NSObject
// Añade los perfiles que falten al launcher_profiles.json de la instancia actual. Hilo principal.
+ (void)seedProfiles;
+ (BOOL)handlesProfile:(nullable NSDictionary *)profile;
// Acceso, Fabric, RealClient, Fabric API y ticket de módulos. Muestra los errores y los avisos.
// completion(YES) en el hilo principal cuando el perfil está listo para que el motor siga.
+ (void)prepareProfileNamed:(NSString *)name
                     status:(void (^)(NSString *text))status
                 completion:(void (^)(BOOL ok))completion;
@end

NS_ASSUME_NONNULL_END
