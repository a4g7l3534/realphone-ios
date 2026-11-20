#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Una build de RealClient del catálogo firmado (mods-manifest-*.json).
@interface RPModEntry : NSObject
@property(nonatomic, readonly) NSString *file;
@property(nonatomic, readonly) NSString *minecraft;
@property(nonatomic, readonly) NSString *sha256;
// fabric, legacy-fabric o neoforge, deducido igual que RealClientCatalog.kt
@property(nonatomic, readonly) NSString *loader;
@property(nonatomic, readonly) NSInteger java;
@end

@interface RPCatalog : NSObject
// Falla entero si una entrada no tiene un nombre de archivo simple, un SHA-256 en hex o una versión.
+ (nullable NSArray<RPModEntry *> *)entriesFromData:(NSData *)data error:(NSString *_Nullable *_Nullable)error;
// Hex en minúsculas, o nil si el archivo no se puede leer.
+ (nullable NSString *)sha256OfFile:(NSString *)path;
+ (nullable NSString *)sha1OfFile:(NSString *)path;
+ (NSString *)sha256Hex:(NSData *)data;
+ (NSString *)hex:(NSData *)data;
+ (BOOL)isHex:(nullable id)value length:(NSUInteger)length;
// 1.21.11 > 1.21.9 > 1.8.9; 26.1.2 > 1.21.11
+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b;
// Nombre de archivo sin carpetas ni "..": lo que se puede unir a una ruta sin salir de ella.
+ (BOOL)isPlainFileName:(nullable id)name;
@end

NS_ASSUME_NONNULL_END
