#import <Foundation/Foundation.h>
#import "RPHTTP.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RPAccess) {
    RPAccessSignedOut,
    // Validada con el servidor ahora
    RPAccessSignedIn,
    // Sin servidor, pero dentro de offlineUntil
    RPAccessOffline,
    // El servidor revocó la cuenta o el dispositivo
    RPAccessBlocked,
};

@interface RPSessionState : NSObject
@property(nonatomic, readonly) RPAccess access;
// Qué pasó y qué hacer, para mostrarlo tal cual
@property(nonatomic, readonly, copy, nullable) NSString *message;
@property(nonatomic, readonly, copy, nullable) NSString *email;
- (BOOL)canPlay;
@end

@protocol RPSecretStore <NSObject>
- (nullable NSData *)dataForKey:(NSString *)key;
- (BOOL)setData:(NSData *)data forKey:(NSString *)key;
- (void)removeKey:(NSString *)key;
@end

// Llavero del iPhone, como hace Amethyst con los tokens de Microsoft.
@interface RPKeychainStore : NSObject <RPSecretStore>
@end

// Acceso por invitación contra backend/src/worker.js, igual que AuthRepository.kt de Android.
// Todos los métodos bloquean: nunca se llaman desde el hilo principal.
@interface RPSession : NSObject
+ (instancetype)shared;
- (instancetype)initWithBaseURL:(NSString *)base
                          store:(id<RPSecretStore>)store
                      transport:(RPTransport)transport
                          nowMs:(int64_t (^)(void))nowMs
                     deviceName:(NSString *)deviceName;
- (BOOL)hasSession;
// Revalida con GET /v1/me (6 s). Sin respuesta vale la sesión guardada hasta offlineUntil.
- (RPSessionState *)restore;
- (RPSessionState *)activateEmail:(NSString *)email code:(NSString *)code;
- (void)logout;
@end

NS_ASSUME_NONNULL_END
