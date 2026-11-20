#import <Security/Security.h>
#import "RPCatalog.h"
#import "RPTicket.h"

static NSString *const RPMojangJoin = @"https://sessionserver.mojang.com/session/minecraft/join";
static const NSTimeInterval RPBudget = 10;
static const NSTimeInterval RPSessionMargin = 60;
static const NSTimeInterval RPReuseMargin = 600;
static const int RPAttempts = 3;
static NSString *const RPOffline = @"offline";

@implementation RPTicketAccount
@end

@interface RPTicketOutcome ()
+ (instancetype)ticket:(NSString *)ticket reason:(NSString *)reason;
@end

@implementation RPTicketOutcome

+ (instancetype)ticket:(NSString *)ticket reason:(NSString *)reason {
    RPTicketOutcome *outcome = [self new];
    outcome.ticket = ticket;
    outcome.reason = reason;
    return outcome;
}

@end

@interface RPTicket ()
@property(nonatomic, copy) NSString *api;
@property(nonatomic, copy) NSString *stateDir;
@property(nonatomic, copy) RPTransport transport;
@property(nonatomic, copy) NSTimeInterval (^now)(void);
@property(nonatomic) NSTimeInterval deadline;
// Motivo por el que se cortó el intento actual; hace de excepción en la cadena de llamadas
@property(nonatomic, copy) NSString *failure;
@end

@implementation RPTicket

- (instancetype)initWithAPI:(NSString *)api
                   stateDir:(NSString *)stateDir
                  transport:(RPTransport)transport
                        now:(NSTimeInterval (^)(void))now {
    self = [super init];
    _api = [api copy];
    _stateDir = [stateDir copy];
    _transport = [transport copy];
    _now = [now copy];
    return self;
}

- (RPTicketOutcome *)ticketFor:(RPTicketAccount *)account {
    @synchronized (RPTicket.class) {
        [NSFileManager.defaultManager createDirectoryAtPath:self.stateDir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *name = account.name;
        if (![RPTicket text:name matches:@"\\A[A-Za-z0-9_]{1,16}\\z"]) {
            return [RPTicketOutcome ticket:nil reason:@"el nombre no admite licencia"];
        }
        self.deadline = self.now() + RPBudget;
        self.failure = nil;

        NSNumber *exp = nil;
        NSString *ticket = [self fetchTicket:account exp:&exp];
        if (ticket) {
            [self keepTicket:ticket exp:exp name:name];
            NSLog(@"[RealPhone] Licencia de módulos de %@ obtenida", name);
            return [RPTicketOutcome ticket:ticket reason:nil];
        }

        NSString *reason = self.failure ?: @"error interno";
        NSString *kept = [self keptTicket:name];
        NSLog(@"[RealPhone] Licencia de módulos de %@: %@%@", name, reason, kept ? @"; se usa la guardada" : @"");
        if (kept) {
            return [RPTicketOutcome ticket:kept reason:[reason stringByAppendingString:@"; se usó la licencia guardada"]];
        }
        return [RPTicketOutcome ticket:nil reason:reason];
    }
}

#pragma mark - Ticket

- (id)fail:(NSString *)reason {
    self.failure = reason;
    return nil;
}

- (NSString *)networkReason {
    if (self.now() >= self.deadline - 0.2) {
        return [NSString stringWithFormat:@"RealMC tardó más de %d s", (int)RPBudget];
    }
    return @"sin conexión con RealMC";
}

- (NSString *)refused:(NSInteger)code {
    switch (code) {
        case 401: return @"RealMC rechazó la sesión";
        case 429: return @"demasiados intentos; espera un rato";
        case 503: return @"RealMC no está disponible";
        default: return [NSString stringWithFormat:@"RealMC respondió HTTP %ld", (long)code];
    }
}

- (NSString *)fetchTicket:(RPTicketAccount *)account exp:(NSNumber **)exp {
    for (int attempt = 0; attempt < RPAttempts; attempt++) {
        RPResponse *response = [self authedPost:account path:@"/v2/mods/ticket" body:@{@"name": account.name}];
        if (!response) {
            return nil;
        }
        if (!response.ok) {
            return [self fail:[self refused:response.status]];
        }
        NSString *ticket = response.jsonObject[@"ticket"];
        NSNumber *expiry = [RPTicket expiryOfTicket:ticket name:account.name];
        if (!expiry) {
            return [self fail:@"RealMC respondió sin un ticket válido"];
        }
        if ([RPTicket engineSafe:ticket]) {
            *exp = expiry;
            return ticket;
        }
    }
    return [self fail:@"el motor no puede pasar el ticket recibido"];
}

- (void)keepTicket:(NSString *)ticket exp:(NSNumber *)exp name:(NSString *)name {
    [self updateState:^(NSMutableDictionary *state) {
        NSMutableDictionary *all = [state[@"tickets"] isKindOfClass:NSDictionary.class] ? [state[@"tickets"] mutableCopy] : [NSMutableDictionary new];
        all[name.lowercaseString] = @{@"ticket": ticket, @"exp": exp};
        state[@"tickets"] = all;
    }];
}

// El último ticket de name, si sigue vigente al menos 10 minutos más.
- (NSString *)keptTicket:(NSString *)name {
    NSDictionary *all = [self readState][@"tickets"];
    NSDictionary *saved = [all isKindOfClass:NSDictionary.class] ? all[name.lowercaseString] : nil;
    if (![saved isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSString *ticket = saved[@"ticket"];
    NSNumber *own = [RPTicket expiryOfTicket:ticket name:name];
    if (!own) {
        return nil;
    }
    double stored = [saved[@"exp"] isKindOfClass:NSNumber.class] ? [saved[@"exp"] doubleValue] : 0;
    BOOL fresh = MIN(own.doubleValue, stored) >= self.now() + RPReuseMargin;
    return fresh && [RPTicket engineSafe:ticket] ? ticket : nil;
}

#pragma mark - Sesión del servicio de mods

- (BOOL)isPremium:(RPTicketAccount *)account {
    // Amethyst deja "offline" como token cuando no pudo renovar la cuenta de Microsoft sin conexión.
    NSString *token = account.accessToken;
    return account.premium && token.length > 0 && ![token isEqualToString:@"0"] && ![token isEqualToString:@"offline"];
}

- (NSString *)uuidOf:(RPTicketAccount *)account {
    return [account.uuid stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString;
}

- (NSString *)accountKey:(RPTicketAccount *)account {
    return [self isPremium:account] ? [@"premium:" stringByAppendingString:[self uuidOf:account]] : RPOffline;
}

// Con sesión (la guardada si sigue vigente; si no, una nueva). Un 401 de la guardada se reintenta una vez.
- (RPResponse *)authedPost:(RPTicketAccount *)account path:(NSString *)path body:(NSDictionary *)body {
    BOOL kept = NO;
    NSString *token = [self sessionToken:account kept:&kept];
    if (!token) {
        return nil;
    }
    NSString *url = [self.api stringByAppendingString:path];
    RPResponse *response = [self post:url body:body bearer:token];
    if (response.status == 401 && kept) {
        [self forgetSession];
        token = [self mintSession:account];
        if (!token) {
            return nil;
        }
        response = [self post:url body:body bearer:token];
    }
    if (response.status == 0) {
        return [self fail:self.networkReason];
    }
    if (response.status == 401) {
        [self forgetSession];
    }
    return response;
}

- (NSString *)sessionToken:(RPTicketAccount *)account kept:(BOOL *)kept {
    // Cualquier sesión puede pedir ticket para cualquier nombre: una cuenta premium también usa la de instalación.
    NSSet *keys = [NSSet setWithObjects:[self accountKey:account], RPOffline, nil];
    NSDictionary *session = [self readState][@"session"];
    if ([session isKindOfClass:NSDictionary.class]) {
        NSString *token = session[@"token"];
        id expiresAt = session[@"expiresAt"];
        BOOL usable = [keys containsObject:session[@"account"] ?: @""]
            && [expiresAt isKindOfClass:NSNumber.class] && [expiresAt doubleValue] > self.now() + RPSessionMargin
            && [token isKindOfClass:NSString.class] && token.length > 0;
        if (usable) {
            *kept = YES;
            return token;
        }
    }
    *kept = NO;
    return [self mintSession:account];
}

- (void)forgetSession {
    [self updateState:^(NSMutableDictionary *state) {
        [state removeObjectForKey:@"session"];
    }];
}

- (NSString *)mintSession:(RPTicketAccount *)account {
    NSDictionary *viaPremium = [self isPremium:account] ? [self premiumSession:account] : nil;
    NSDictionary *reply = viaPremium ?: [self installSession];
    if (!reply) {
        return nil;
    }
    NSString *token = reply[@"session"];
    if (![token isKindOfClass:NSString.class] || token.length == 0) {
        return [self fail:@"RealMC no dio una sesión"];
    }
    id exp = reply[@"expiresAt"];
    NSString *owner = viaPremium ? [self accountKey:account] : RPOffline;
    [self updateState:^(NSMutableDictionary *state) {
        if ([exp isKindOfClass:NSNumber.class]) {
            state[@"session"] = @{@"account": owner, @"token": token, @"expiresAt": exp};
        } else {
            [state removeObjectForKey:@"session"];
        }
    }];
    return token;
}

// Prueba con Mojang que la cuenta es suya. nil si algo falla (se sigue con la de instalación).
- (NSDictionary *)premiumSession:(RPTicketAccount *)account {
    NSString *uuid = [self uuidOf:account];
    NSData *secret = [RPTicket randomBytes:32];
    if (!secret) {
        return nil;
    }
    RPResponse *challenge = [self post:[self.api stringByAppendingString:@"/v2/mods/auth/challenge"]
                                  body:@{@"name": account.name, @"uuid": uuid, @"proof": [RPTicket proofForSecret:secret]}
                                bearer:nil];
    NSString *nonce = challenge.ok ? challenge.jsonObject[@"nonce"] : nil;
    if (![RPCatalog isHex:nonce length:40]) {
        return nil;
    }
    // 204 es la única respuesta correcta del join de Mojang.
    RPResponse *joined = [self post:RPMojangJoin
                               body:@{@"accessToken": account.accessToken, @"selectedProfile": uuid,
                                      @"serverId": [RPTicket joinIdForNonce:nonce uuid:uuid]}
                             bearer:nil];
    if (joined.status != 204) {
        return nil;
    }
    RPResponse *verified = [self post:[self.api stringByAppendingString:@"/v2/mods/auth/verify"]
                                 body:@{@"name": account.name, @"uuid": uuid, @"nonce": nonce, @"secret": [RPCatalog hex:secret]}
                               bearer:nil];
    return verified.ok ? verified.jsonObject : nil;
}

- (NSDictionary *)installSession {
    NSString *installId = [self modInstallId];
    if (!installId) {
        return [self fail:@"no se pudo crear el id de instalación"];
    }
    RPResponse *response = [self post:[self.api stringByAppendingString:@"/v2/mods/auth/install"]
                                 body:@{@"installId": installId}
                               bearer:nil];
    if (response.status == 0) {
        return [self fail:self.networkReason];
    }
    if (response.status == 403) {
        return [self fail:@"RealMC no admite ahora cuentas sin premium o bloqueó este iPhone"];
    }
    if (!response.ok) {
        return [self fail:[self refused:response.status]];
    }
    return response.jsonObject ?: [self fail:@"RealMC no dio una sesión"];
}

// Id de instalación para el servicio de mods (distinto del de presencia).
- (NSString *)modInstallId {
    NSString *path = [self.stateDir stringByAppendingPathComponent:@"mod-install-id.txt"];
    NSString *saved = [[NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([RPCatalog isHex:saved length:64]) {
        return saved;
    }
    NSData *bytes = [RPTicket randomBytes:32];
    if (!bytes) {
        return nil;
    }
    NSString *installId = [RPCatalog hex:bytes];
    if (![installId writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
        return nil;
    }
    return installId;
}

#pragma mark - Red y estado

- (RPResponse *)post:(NSString *)url body:(NSDictionary *)body bearer:(NSString *)bearer {
    NSTimeInterval left = self.deadline - self.now();
    if (left <= 0.2) {
        return [RPResponse failure:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
    }
    return self.transport([RPHTTP request:@"POST" url:url json:body bearer:bearer timeout:MIN(6, left)]);
}

- (NSString *)statePath {
    return [self.stateDir stringByAppendingPathComponent:@"mod-state.json"];
}

- (NSMutableDictionary *)readState {
    NSData *data = [NSData dataWithContentsOfFile:self.statePath];
    id state = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    return [state isKindOfClass:NSMutableDictionary.class] ? state : [NSMutableDictionary new];
}

- (void)updateState:(void (^)(NSMutableDictionary *state))change {
    NSMutableDictionary *state = [self readState];
    change(state);
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:&error];
    if (!data || ![data writeToFile:self.statePath options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[RealPhone] No se pudo guardar el estado de la licencia: %@", error.localizedDescription);
    }
}

#pragma mark - Reglas

+ (BOOL)text:(id)text matches:(NSString *)pattern {
    return [text isKindOfClass:NSString.class]
        && [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}

+ (NSData *)randomBytes:(size_t)count {
    NSMutableData *data = [NSMutableData dataWithLength:count];
    if (SecRandomCopyBytes(kSecRandomDefault, count, data.mutableBytes) != errSecSuccess) {
        return nil;
    }
    return data;
}

+ (BOOL)isInteger:(id)value {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) {
        return NO;
    }
    char type = [value objCType][0];
    return type != '\0' && strchr("cCsSiIlLqQ", type) != NULL;
}

// base64url sin relleno y en su forma canónica, como Base64.getUrlDecoder() + re-codificar en Kotlin.
+ (NSData *)base64URL:(NSString *)text {
    if (![self text:text matches:@"\\A[A-Za-z0-9_-]+\\z"]) {
        return nil;
    }
    NSString *standard = [[text stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
        stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger rest = standard.length % 4;
    if (rest == 1) {
        return nil;
    }
    if (rest > 0) {
        standard = [standard stringByPaddingToLength:standard.length + 4 - rest withString:@"=" startingAtIndex:0];
    }
    NSData *bytes = [[NSData alloc] initWithBase64EncodedString:standard options:0];
    if (!bytes) {
        return nil;
    }
    NSString *again = [[[[bytes base64EncodedStringWithOptions:0]
        stringByReplacingOccurrencesOfString:@"+" withString:@"-"]
        stringByReplacingOccurrencesOfString:@"/" withString:@"_"]
        stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return [again isEqualToString:text] ? bytes : nil;
}

+ (NSNumber *)expiryOfTicket:(NSString *)ticket name:(NSString *)name {
    if (![ticket isKindOfClass:NSString.class]) {
        return nil;
    }
    NSRange dot = [ticket rangeOfString:@"."];
    if (dot.location == NSNotFound || dot.location == 0 ||
        [ticket rangeOfString:@"." options:NSBackwardsSearch].location != dot.location) {
        return nil;
    }
    NSData *signature = [self base64URL:[ticket substringFromIndex:dot.location + 1]];
    NSData *payload = [self base64URL:[ticket substringToIndex:dot.location]];
    if (signature.length != 64 || !payload) {
        return nil;
    }
    NSDictionary *claims = [NSJSONSerialization JSONObjectWithData:payload options:0 error:nil];
    if (![claims isKindOfClass:NSDictionary.class] || ![self isInteger:claims[@"v"]] || [claims[@"v"] longLongValue] != 1) {
        return nil;
    }
    NSString *owner = claims[@"n"];
    if (![owner isKindOfClass:NSString.class] || [owner caseInsensitiveCompare:name] != NSOrderedSame) {
        return nil;
    }
    return [self isInteger:claims[@"exp"]] ? @([claims[@"exp"] longLongValue]) : nil;
}

+ (BOOL)engineSafe:(NSString *)ticket {
    if (![self text:ticket matches:@"\\A[A-Za-z0-9_.-]+\\z"]) {
        return NO;
    }
    // El motor separa los argumentos de Java por estos prefijos: un ticket que los tenga llegaría partido.
    for (NSString *split in @[@"--", @"-D", @"-X", @"-javaagent:", @"-verbose"]) {
        if ([ticket containsString:split]) {
            return NO;
        }
    }
    return YES;
}

+ (NSString *)joinIdForNonce:(NSString *)nonce uuid:(NSString *)uuid {
    NSString *text = [NSString stringWithFormat:@"realmc-auth-v2\n%@\n%@", nonce, uuid];
    NSString *digest = [RPCatalog sha256Hex:[text dataUsingEncoding:NSUTF8StringEncoding]];
    return [@"rmc" stringByAppendingString:[digest substringToIndex:37]];
}

+ (NSString *)proofForSecret:(NSData *)secret {
    return [RPCatalog sha256Hex:secret];
}

@end
