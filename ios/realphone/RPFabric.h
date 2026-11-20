#import <Foundation/Foundation.h>
#import "RPHTTP.h"

NS_ASSUME_NONNULL_BEGIN

// Fabric y Legacy Fabric como en RealPhoneBridge.java de Android.
@interface RPFabric : NSObject
- (instancetype)initWithTransport:(RPTransport)transport;
// Guarda el perfil del primer loader estable en versions/<id>/<id>.json y devuelve el id.
- (nullable NSString *)installLoader:(NSString *)loader
                                  mc:(NSString *)mc
                         versionsDir:(NSString *)versions
                               error:(NSString *_Nullable *_Nullable)error;
// Fabric API de Modrinth para mc, con su SHA-1 comprobado. Sin red vale una Fabric API ya instalada.
- (BOOL)ensureFabricApi:(NSString *)mc mods:(NSString *)mods error:(NSString *_Nullable *_Nullable)error;
@end

NS_ASSUME_NONNULL_END
