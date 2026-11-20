#import <Security/Security.h>
#include <sys/utsname.h>
#import "RPConfig.h"
#import "RPSession.h"

static NSString *const RPSessionKey = @"session";
static NSString *const RPDeviceKey = @"device";

@interface RPSessionState ()
+ (instancetype)access:(RPAccess)access message:(NSString *)message email:(NSString *)email;
@end

@implementation RPSessionState

+ (instancetype)access:(RPAccess)access message:(NSString *)message email:(NSString *)email {
    RPSessionState *state = [self new];
    state->_access = access;
    state->_message = [message copy];
    state->_email = [email copy];
    return state;
}

- (BOOL)canPlay {
    return self.access == RPAccessSignedIn || self.access == RPAccessOffline;
}

@end

@implementation RPKeychainStore

- (NSMutableDictionary *)queryFor:(NSString *)key {
    return @{
        (id)kSecClass: (id)kSecClassGenericPassword,
        (id)kSecAttrService: @"com.nationcode.realphone",
        (id)kSecAttrAccount: key,
    }.mutableCopy;
}

- (NSData *)dataForKey:(NSString *)key {
    NSMutableDictionary *query = [self queryFor:key];
    query[(id)kSecMatchLimit] = (id)kSecMatchLimitOne;
    query[(id)kSecReturnData] = (id)kCFBooleanTrue;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) {
        return nil;
    }
    return (__bridge_transfer NSData *)result;
}

- (BOOL)setData:(NSData *)data forKey:(NSString *)key {
    NSDictionary *query = [self queryFor:key];
    // Primero se actualiza: si borrar y añadir fallara a medias se perdería la sesión.
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(id)kSecValueData: data});
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [self queryFor:key];
        item[(id)kSecAttrAccessible] = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        item[(id)kSecValueData] = data;
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    if (status != errSecSuccess) {
        NSLog(@"[RealPhone] El llavero rechazó '%@' (OSStatus %d)", key, (int)status);
    }
    return status == errSecSuccess;
}

- (void)removeKey:(NSString *)key {
    SecItemDelete((__bridge CFDictionaryRef)[self queryFor:key]);
}

@end

@interface RPSession ()
@property(nonatomic, copy) NSString *base;
@property(nonatomic) id<RPSecretStore> store;
@property(nonatomic, copy) RPTransport transport;
@property(nonatomic, copy) int64_t (^nowMs)(void);
@property(nonatomic, copy) NSString *deviceName;
@end

@implementation RPSession

+ (instancetype)shared {
    static RPSession *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct utsname info;
        uname(&info);
        shared = [[RPSession alloc] initWithBaseURL:RP_BACKEND_URL
                                              store:[RPKeychainStore new]
                                          transport:RPHTTP.system
                                              nowMs:^int64_t(void) {
            return (int64_t)(NSDate.date.timeIntervalSince1970 * 1000);
        }
                                         deviceName:[NSString stringWithFormat:@"Apple %s", info.machine]];
    });
    return shared;
}

- (instancetype)initWithBaseURL:(NSString *)base
                          store:(id<RPSecretStore>)store
                      transport:(RPTransport)transport
                          nowMs:(int64_t (^)(void))nowMs
                     deviceName:(NSString *)deviceName {
    self = [super init];
    _base = [base copy];
    _store = store;
    _transport = [transport copy];
    _nowMs = [nowMs copy];
    _deviceName = [deviceName copy];
    return self;
}

#pragma mark - Guardado

- (NSMutableDictionary *)load {
    NSData *data = [self.store dataForKey:RPSessionKey];
    if (!data) {
        return nil;
    }
    NSMutableDictionary *session = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
    BOOL valid = [session isKindOfClass:NSMutableDictionary.class]
        && [session[@"token"] isKindOfClass:NSString.class]
        && [session[@"offlineUntil"] isKindOfClass:NSNumber.class];
    if (!valid) {
        NSLog(@"[RealPhone] La sesión guardada no se puede leer; se descarta");
        [self.store removeKey:RPSessionKey];
        return nil;
    }
    return session;
}

- (BOOL)save:(NSDictionary *)session {
    NSData *data = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
    return data && [self.store setData:data forKey:RPSessionKey];
}

- (BOOL)hasSession {
    return [self load] != nil;
}

- (NSString *)deviceId {
    NSData *data = [self.store dataForKey:RPDeviceKey];
    NSString *saved = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
    if (saved.length >= 16) {
        return saved;
    }
    NSString *fresh = NSUUID.UUID.UUIDString.lowercaseString;
    [self.store setData:[fresh dataUsingEncoding:NSUTF8StringEncoding] forKey:RPDeviceKey];
    return fresh;
}

static NSString *RPServerMessage(RPResponse *response, NSString *fallback) {
    NSString *message = response.jsonObject[@"message"];
    return [message isKindOfClass:NSString.class] && message.length > 0 ? message : fallback;
}

static NSString *RPEmailOf(NSDictionary *session) {
    NSDictionary *user = session[@"user"];
    if (![user isKindOfClass:NSDictionary.class] || ![user[@"email"] isKindOfClass:NSString.class]) {
        return nil;
    }
    return user[@"email"];
}

#pragma mark - Acceso

- (RPSessionState *)restore {
    NSMutableDictionary *session = [self load];
    if (!session) {
        return [RPSessionState access:RPAccessSignedOut message:nil email:nil];
    }

    NSURLRequest *request = [RPHTTP request:@"GET" url:[self.base stringByAppendingString:@"/v1/me"]
                                       json:nil bearer:session[@"token"] timeout:6];
    RPResponse *response = self.transport(request);
    if (response.status == 401 || response.status == 403) {
        [self.store removeKey:RPSessionKey];
        NSLog(@"[RealPhone] Acceso revocado por el servidor (%ld)", (long)response.status);
        return [RPSessionState access:RPAccessBlocked
                              message:RPServerMessage(response, @"Tu cuenta o este dispositivo fueron desactivados por NationCode.")
                                email:RPEmailOf(session)];
    }

    NSDictionary *body = response.status == 200 ? response.jsonObject : nil;
    BOOL fresh = [body[@"user"] isKindOfClass:NSDictionary.class]
        && [body[@"expiresAt"] isKindOfClass:NSNumber.class]
        && [body[@"offlineUntil"] isKindOfClass:NSNumber.class];
    if (!fresh) {
        return [self offlineState:session];
    }
    session[@"user"] = body[@"user"];
    session[@"expiresAt"] = body[@"expiresAt"];
    session[@"offlineUntil"] = body[@"offlineUntil"];
    if ([body[@"token"] isKindOfClass:NSString.class]) {
        session[@"token"] = body[@"token"];
    }
    if (![self save:session]) {
        NSLog(@"[RealPhone] No se pudo actualizar la sesión en el llavero");
    }
    return [RPSessionState access:RPAccessSignedIn message:nil email:RPEmailOf(session)];
}

- (RPSessionState *)offlineState:(NSDictionary *)session {
    if (self.nowMs() < [session[@"offlineUntil"] longLongValue]) {
        NSLog(@"[RealPhone] Sin conexión con NationCode; se usa la autorización sin conexión");
        return [RPSessionState access:RPAccessOffline message:nil email:RPEmailOf(session)];
    }
    return [RPSessionState access:RPAccessSignedOut
                          message:@"Necesitas conexión para renovar tu acceso. Conéctate a internet y abre RealPhone otra vez."
                            email:RPEmailOf(session)];
}

- (RPSessionState *)activateEmail:(NSString *)email code:(NSString *)code {
    NSCharacterSet *blank = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    NSString *cleanEmail = [email stringByTrimmingCharactersInSet:blank].lowercaseString;
    NSString *cleanCode = [code stringByTrimmingCharactersInSet:blank];
    if (cleanEmail.length == 0 || cleanCode.length == 0) {
        return [RPSessionState access:RPAccessSignedOut message:@"Escribe tu correo y el código de invitación." email:nil];
    }

    NSString *deviceId = [self deviceId];
    NSDictionary *payload = @{
        @"email": cleanEmail,
        @"inviteCode": cleanCode,
        @"deviceId": deviceId,
        @"deviceName": self.deviceName,
        @"appVersion": RP_APP_VERSION,
    };
    RPResponse *response = self.transport([RPHTTP request:@"POST" url:[self.base stringByAppendingString:@"/v1/activate"]
                                                     json:payload bearer:nil timeout:15]);
    if (response.status == 0) {
        return [RPSessionState access:RPAccessSignedOut
                              message:@"No hay conexión con NationCode. Revisa internet y vuelve a intentarlo."
                                email:cleanEmail];
    }
    if (!response.ok) {
        NSString *fallback = [NSString stringWithFormat:@"NationCode rechazó la activación (HTTP %ld). Vuelve a intentarlo más tarde.", (long)response.status];
        return [RPSessionState access:RPAccessSignedOut message:RPServerMessage(response, fallback) email:cleanEmail];
    }

    NSDictionary *body = response.jsonObject;
    NSString *token = body[@"token"];
    BOOL complete = [token isKindOfClass:NSString.class] && token.length > 0
        && [body[@"expiresAt"] isKindOfClass:NSNumber.class]
        && [body[@"offlineUntil"] isKindOfClass:NSNumber.class];
    if (!complete) {
        return [RPSessionState access:RPAccessSignedOut
                              message:@"NationCode respondió sin una sesión. Vuelve a intentarlo."
                                email:cleanEmail];
    }
    NSDictionary *session = @{
        @"token": token,
        @"user": [body[@"user"] isKindOfClass:NSDictionary.class] ? body[@"user"] : @{@"email": cleanEmail},
        @"deviceId": deviceId,
        @"issuedAt": @(self.nowMs()),
        @"expiresAt": body[@"expiresAt"],
        @"offlineUntil": body[@"offlineUntil"],
    };
    if (![self save:session]) {
        // El código ya se gastó en el servidor: sin llavero no hay forma de recuperar esta activación.
        return [RPSessionState access:RPAccessSignedOut
                              message:@"El iPhone se activó, pero no se pudo guardar el acceso en el llavero. Pide un código nuevo a NationCode."
                                email:cleanEmail];
    }
    NSLog(@"[RealPhone] Dispositivo activado");
    return [RPSessionState access:RPAccessSignedIn message:nil email:cleanEmail];
}

- (void)logout {
    NSDictionary *session = [self load];
    if (session) {
        self.transport([RPHTTP request:@"POST" url:[self.base stringByAppendingString:@"/v1/logout"]
                                  json:nil bearer:session[@"token"] timeout:8]);
    }
    [self.store removeKey:RPSessionKey];
}

@end
