#import <Foundation/Foundation.h>
#import "RPCatalog.h"

NS_ASSUME_NONNULL_BEGIN

// Archivos de la carpeta mods/ de una instancia. Lo que sobra se renombra a .disabled, nunca se borra.
@interface RPMods : NSObject
// Copia el jar de RealClient a mods/ solo si su SHA-256 coincide con el catálogo. Los demás realmc-client*.jar
// se desactivan aunque falle, para no arrancar con el RealClient de otra versión.
+ (BOOL)installClient:(RPModEntry *)entry
                 from:(NSString *)source
             intoMods:(NSString *)mods
                error:(NSString *_Nullable *_Nullable)error;
// Desactiva los .jar que empiezan por prefix, salvo keep.
+ (void)disableJarsWithPrefix:(NSString *)prefix inMods:(NSString *)mods keeping:(nullable NSString *)keep;
// Mueve tmp a dest reemplazando dest si existía.
+ (BOOL)replace:(NSString *)dest with:(NSString *)tmp;
@end

NS_ASSUME_NONNULL_END
