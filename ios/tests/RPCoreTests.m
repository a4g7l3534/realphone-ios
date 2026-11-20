// Pruebas de la lógica de RealPhone iOS que no depende de UIKit ni de Amethyst.
// Se compilan y ejecutan en macOS (ver .github/workflows/realphone-ios.yml):
//   clang -fobjc-arc -Wall -Werror ios/realphone/RP{Catalog,HTTP,Mods,Fabric,Ticket,Session}.m ios/tests/RPCoreTests.m \
//         -framework Foundation -framework Security -o rptests && ./rptests <mods-manifest-0.6.6.json>
#import <Foundation/Foundation.h>
#import "../realphone/RPCatalog.h"
#import "../realphone/RPFabric.h"
#import "../realphone/RPMods.h"
#import "../realphone/RPSession.h"
#import "../realphone/RPTicket.h"

static int checks = 0;
static int failures = 0;

#define CHECK(cond, ...) do { \
    checks++; \
    if (!(cond)) { \
        failures++; \
        fprintf(stderr, "FALLO %s:%d: %s\n", __FILE__, __LINE__, [[NSString stringWithFormat:__VA_ARGS__] UTF8String]); \
    } \
} while (0)

static NSString *const TicketSteve = @"eyJ2IjoxLCJuIjoiU3RldmUiLCJleHAiOjIwMDAwMDAwMDB9."
    "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ";
static NSString *const Signature64 = @"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQ";
static NSString *const Signature63 = @"AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB";
static const NSTimeInterval Now = 1900000000;

#pragma mark - Utilidades

@interface RPMemoryStore : NSObject <RPSecretStore>
@property(nonatomic) NSMutableDictionary<NSString *, NSData *> *items;
@end

@implementation RPMemoryStore
- (instancetype)init {
    self = [super init];
    _items = [NSMutableDictionary new];
    return self;
}
- (NSData *)dataForKey:(NSString *)key {
    return self.items[key];
}
- (BOOL)setData:(NSData *)data forKey:(NSString *)key {
    self.items[key] = data;
    return YES;
}
- (void)removeKey:(NSString *)key {
    [self.items removeObjectForKey:key];
}
@end

typedef RPResponse *(^RPRoute)(NSURLRequest *request);

// Servidor falso: responde por "MÉTODO /ruta" y guarda cada petición.
@interface RPFakeServer : NSObject
@property(nonatomic) NSMutableArray<NSURLRequest *> *requests;
@property(nonatomic) NSMutableDictionary<NSString *, RPRoute> *routes;
@property(nonatomic) BOOL down;
- (RPTransport)transport;
@end

@implementation RPFakeServer
- (instancetype)init {
    self = [super init];
    _requests = [NSMutableArray new];
    _routes = [NSMutableDictionary new];
    return self;
}
- (RPTransport)transport {
    __weak RPFakeServer *weakSelf = self;
    return ^RPResponse *(NSURLRequest *request) {
        RPFakeServer *server = weakSelf;
        [server.requests addObject:request];
        if (server.down) {
            return [RPResponse failure:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        }
        RPRoute route = server.routes[[NSString stringWithFormat:@"%@ %@", request.HTTPMethod, request.URL.path]];
        return route ? route(request) : [RPResponse status:404 body:nil];
    };
}
- (NSArray<NSURLRequest *> *)requestsTo:(NSString *)path {
    return [self.requests filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURLRequest *r, NSDictionary *bindings) {
        return [r.URL.path isEqualToString:path];
    }]];
}
@end

static NSData *JSONData(id object) {
    return [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
}

static RPResponse *Reply(NSInteger status, id body) {
    return [RPResponse status:status body:body ? JSONData(body) : nil];
}

static NSDictionary *BodyOf(NSURLRequest *request) {
    return request.HTTPBody ? [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:nil] : nil;
}

static NSString *TempDir(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"rp-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

static void WriteText(NSString *text, NSString *path) {
    [text writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static NSString *ReadText(NSString *path) {
    return [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
}

static RPModEntry *EntryFor(NSString *file, NSString *minecraft, NSString *content) {
    NSString *sha = [RPCatalog sha256Hex:[content dataUsingEncoding:NSUTF8StringEncoding]];
    NSData *manifest = JSONData(@{@"mods": @[@{@"file": file, @"minecraft": @[minecraft], @"sha256": sha, @"java": @21}]});
    return [RPCatalog entriesFromData:manifest error:nil].firstObject;
}

#pragma mark - Catálogo (S3)

static void TestCatalog(NSString *manifestPath) {
    NSString *error = nil;
    NSArray<RPModEntry *> *entries = [RPCatalog entriesFromData:[NSData dataWithContentsOfFile:manifestPath] error:&error];
    CHECK(entries.count == 31, @"el catálogo 0.6.6 tiene 31 builds, hay %lu (%@)", (unsigned long)entries.count, error);
    NSUInteger neoforge = 0;
    for (RPModEntry *entry in entries) {
        if ([entry.minecraft isEqualToString:@"1.8.9"]) {
            CHECK([entry.loader isEqualToString:@"legacy-fabric"], @"1.8.9 es Legacy Fabric, no %@", entry.loader);
            CHECK(entry.java == 8, @"1.8.9 usa Java 8");
        }
        if ([entry.loader isEqualToString:@"neoforge"]) {
            neoforge++;
        }
        if ([entry.file isEqualToString:@"realmc-client-0.6.6+mc1.21.11.jar"]) {
            CHECK([entry.loader isEqualToString:@"fabric"] && entry.java == 21, @"1.21.11 es Fabric con Java 21");
            CHECK([entry.sha256 isEqualToString:@"0b1d42ec1070fb29129aeae5d1bd39f7f43da0951f679496c68578756e4383ee"], @"SHA-256 de 1.21.11");
        }
    }
    CHECK(neoforge == 1, @"una sola build NeoForge");

    NSString *sha = [@"" stringByPaddingToLength:64 withString:@"a" startingAtIndex:0];
    NSArray *bad = @[
        @{@"file": @"../fuera.jar", @"minecraft": @[@"1.21"], @"sha256": sha},
        @{@"file": @"ok.jar", @"minecraft": @[@"1.21/.."], @"sha256": sha},
        @{@"file": @"ok.jar", @"minecraft": @[@"1.21"], @"sha256": @"ABC"},
    ];
    for (NSDictionary *mod in bad) {
        error = nil;
        CHECK([RPCatalog entriesFromData:JSONData(@{@"mods": @[mod]}) error:&error] == nil && error.length > 0,
              @"se rechaza la entrada %@", mod);
    }

    CHECK([RPCatalog compareVersion:@"1.21.11" to:@"1.21.9"] == NSOrderedDescending, @"1.21.11 > 1.21.9");
    CHECK([RPCatalog compareVersion:@"26.1.2" to:@"1.21.11"] == NSOrderedDescending, @"26.1.2 > 1.21.11");
    CHECK([RPCatalog compareVersion:@"1.18" to:@"1.18.1"] == NSOrderedAscending, @"1.18 < 1.18.1");
    CHECK([RPCatalog compareVersion:@"1.8.9" to:@"1.17.1"] == NSOrderedAscending, @"1.8.9 < 1.17.1");
    CHECK([[RPCatalog sha256Hex:[@"jar bueno" dataUsingEncoding:NSUTF8StringEncoding]]
           isEqualToString:@"817945e61a60ab32443b5781bbef078ca4bb4bc3488a8a46ba2cae3add20bb18"], @"SHA-256 conocido");
}

#pragma mark - Jar de RealClient en mods/ (S3)

static void TestInstallClient(void) {
    NSString *dir = TempDir();
    NSString *mods = [dir stringByAppendingPathComponent:@"mods"];
    NSString *source = [dir stringByAppendingPathComponent:@"fuente.jar"];
    NSString *file = @"realmc-client-0.6.6+mc1.21.11.jar";
    RPModEntry *entry = EntryFor(file, @"1.21.11", @"jar bueno");
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm createDirectoryAtPath:mods withIntermediateDirectories:YES attributes:nil error:nil];
    WriteText(@"otra versión", [mods stringByAppendingPathComponent:@"realmc-client-0.6.6+mc1.20.1.jar"]);
    WriteText(@"no se toca", [mods stringByAppendingPathComponent:@"sodium.jar"]);

    // Hash correcto
    WriteText(@"jar bueno", source);
    NSString *error = nil;
    CHECK([RPMods installClient:entry from:source intoMods:mods error:&error], @"instala el jar verificado: %@", error);
    CHECK([ReadText([mods stringByAppendingPathComponent:file]) isEqualToString:@"jar bueno"], @"el jar queda en mods");
    CHECK([fm fileExistsAtPath:[mods stringByAppendingPathComponent:@"realmc-client-0.6.6+mc1.20.1.jar.disabled"]], @"el RealClient de otra versión se desactiva");
    CHECK([fm fileExistsAtPath:[mods stringByAppendingPathComponent:@"sodium.jar"]], @"los demás mods no se tocan");
    CHECK([RPMods installClient:entry from:source intoMods:mods error:&error], @"una segunda vez también vale");

    // Hash incorrecto
    WriteText(@"jar cambiado", source);
    error = nil;
    CHECK(![RPMods installClient:entry from:source intoMods:mods error:&error], @"un jar que no coincide no se instala");
    CHECK([error containsString:@"no coincide"], @"el motivo lo dice: %@", error);
    CHECK(![fm fileExistsAtPath:[mods stringByAppendingPathComponent:file]], @"no queda ningún RealClient activo");

    // Archivo ausente
    [fm removeItemAtPath:source error:nil];
    error = nil;
    CHECK(![RPMods installClient:entry from:source intoMods:mods error:&error], @"sin jar no se instala");
    CHECK([error containsString:@"no trae RealClient"], @"el motivo lo dice: %@", error);
}

#pragma mark - Reglas del ticket (S5)

static void TestTicketRules(void) {
    CHECK([[RPTicket expiryOfTicket:TicketSteve name:@"Steve"] isEqualToNumber:@2000000000], @"exp del ticket");
    CHECK([[RPTicket expiryOfTicket:TicketSteve name:@"steve"] isEqualToNumber:@2000000000], @"el nombre no distingue mayúsculas");
    CHECK([RPTicket expiryOfTicket:TicketSteve name:@"Alex"] == nil, @"un ticket de otro jugador no vale");
    NSString *decimal = [@"eyJ2IjoxLjUsIm4iOiJTdGV2ZSIsImV4cCI6MjAwMDAwMDAwMH0." stringByAppendingString:Signature64];
    CHECK([RPTicket expiryOfTicket:decimal name:@"Steve"] == nil, @"v debe ser entero");
    NSString *shortSig = [@"eyJ2IjoxLCJuIjoiU3RldmUiLCJleHAiOjIwMDAwMDAwMDB9." stringByAppendingString:Signature63];
    CHECK([RPTicket expiryOfTicket:shortSig name:@"Steve"] == nil, @"la firma mide 64 bytes");
    CHECK([RPTicket expiryOfTicket:[TicketSteve stringByAppendingString:@".x"] name:@"Steve"] == nil, @"un solo punto");
    CHECK([RPTicket expiryOfTicket:[TicketSteve stringByAppendingString:@"="] name:@"Steve"] == nil, @"sin relleno");
    CHECK([RPTicket expiryOfTicket:nil name:@"Steve"] == nil, @"nil no es un ticket");

    CHECK([RPTicket engineSafe:TicketSteve], @"un ticket normal pasa al motor");
    CHECK(![RPTicket engineSafe:@"abc-Dfoo"], @"-D partiría el argumento");
    CHECK(![RPTicket engineSafe:@"abc--x"], @"-- partiría el argumento");
    CHECK(![RPTicket engineSafe:@"a b"], @"sin espacios");
    CHECK(![RPTicket engineSafe:@"abc\n"], @"sin saltos de línea");
    CHECK(![RPTicket engineSafe:@""], @"vacío no vale");

    CHECK([[RPTicket joinIdForNonce:@"0123456789abcdef0123456789abcdef01234567" uuid:@"069a79f444e94726a5befca90e38aaf5"]
           isEqualToString:@"rmc3b99bac126c4290fce04148b4f95535040ee5"], @"serverId del join, igual que RealClientTicket.kt");
}

#pragma mark - Flujo del ticket (S5)

static RPTicket *TicketClient(RPFakeServer *server, NSString *stateDir) {
    return [[RPTicket alloc] initWithAPI:@"https://presence.test" stateDir:stateDir transport:server.transport now:^NSTimeInterval(void) {
        return Now;
    }];
}

static RPTicketAccount *Account(NSString *name, BOOL premium) {
    RPTicketAccount *account = [RPTicketAccount new];
    account.name = name;
    account.uuid = @"069a79f4-44e9-4726-a5be-fca90e38aaf5";
    account.premium = premium;
    account.accessToken = premium ? @"token-de-mojang" : nil;
    return account;
}

static void TestTicketFlow(void) {
    NSString *state = TempDir();
    RPFakeServer *server = [RPFakeServer new];
    server.routes[@"POST /v2/mods/auth/install"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"session": @"sesion-instalacion", @"expiresAt": @(Now + 3600)});
    };
    server.routes[@"POST /v2/mods/ticket"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"ticket": TicketSteve});
    };

    RPTicketOutcome *outcome = [TicketClient(server, state) ticketFor:Account(@"Steve", NO)];
    CHECK([outcome.ticket isEqualToString:TicketSteve] && outcome.reason == nil, @"sin premium: ticket por instalación (%@)", outcome.reason);
    NSURLRequest *ticketRequest = [server requestsTo:@"/v2/mods/ticket"].firstObject;
    CHECK([[ticketRequest valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer sesion-instalacion"], @"el ticket se pide con la sesión");
    NSString *installId = ReadText([state stringByAppendingPathComponent:@"mod-install-id.txt"]);
    CHECK([RPCatalog isHex:installId length:64], @"el id de instalación se guarda");
    CHECK([BodyOf([server requestsTo:@"/v2/mods/auth/install"].firstObject)[@"installId"] isEqualToString:installId], @"y es el que se envía");

    [server.requests removeAllObjects];
    outcome = [TicketClient(server, state) ticketFor:Account(@"Steve", NO)];
    CHECK(outcome.ticket && [server requestsTo:@"/v2/mods/auth/install"].count == 0, @"la sesión guardada se reutiliza");

    server.down = YES;
    outcome = [TicketClient(server, state) ticketFor:Account(@"Steve", NO)];
    CHECK([outcome.ticket isEqualToString:TicketSteve], @"sin conexión vale el ticket guardado");
    CHECK([outcome.reason containsString:@"sin conexión con RealMC"] && [outcome.reason containsString:@"guardada"], @"y lo dice: %@", outcome.reason);

    NSString *fresh = TempDir();
    outcome = [TicketClient(server, fresh) ticketFor:Account(@"Steve", NO)];
    CHECK(outcome.ticket == nil && [outcome.reason isEqualToString:@"sin conexión con RealMC"], @"sin conexión ni ticket guardado: %@", outcome.reason);

    server.down = NO;
    server.routes[@"POST /v2/mods/auth/install"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(403, @{@"error": @"forbidden"});
    };
    outcome = [TicketClient(server, TempDir()) ticketFor:Account(@"Steve", NO)];
    CHECK(outcome.ticket == nil && [outcome.reason containsString:@"no admite ahora cuentas sin premium"], @"403 de instalación: %@", outcome.reason);

    [server.requests removeAllObjects];
    outcome = [TicketClient(server, TempDir()) ticketFor:Account(@"Demo.Steve", NO)];
    CHECK(outcome.ticket == nil && server.requests.count == 0, @"un nombre inválido no llega a la red");
}

static void TestPremiumTicket(void) {
    RPFakeServer *server = [RPFakeServer new];
    NSString *nonce = @"0123456789abcdef0123456789abcdef01234567";
    server.routes[@"POST /v2/mods/auth/challenge"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"nonce": nonce});
    };
    server.routes[@"POST /session/minecraft/join"] = ^RPResponse *(NSURLRequest *r) {
        return [RPResponse status:204 body:nil];
    };
    server.routes[@"POST /v2/mods/auth/verify"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"session": @"sesion-premium", @"expiresAt": @(Now + 3600)});
    };
    server.routes[@"POST /v2/mods/ticket"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"ticket": TicketSteve});
    };

    RPTicketOutcome *outcome = [TicketClient(server, TempDir()) ticketFor:Account(@"Steve", YES)];
    CHECK([outcome.ticket isEqualToString:TicketSteve], @"premium: ticket (%@)", outcome.reason);
    NSURLRequest *join = [server requestsTo:@"/session/minecraft/join"].firstObject;
    CHECK([join.URL.host isEqualToString:@"sessionserver.mojang.com"], @"el join va a Mojang");
    CHECK([BodyOf(join)[@"serverId"] isEqualToString:[RPTicket joinIdForNonce:nonce uuid:@"069a79f444e94726a5befca90e38aaf5"]], @"serverId del join");
    for (NSURLRequest *request in server.requests) {
        if ([request.URL.host isEqualToString:@"presence.test"]) {
            NSString *body = [[NSString alloc] initWithData:request.HTTPBody encoding:NSUTF8StringEncoding];
            CHECK(![body containsString:@"token-de-mojang"], @"el token de Mojang no va a RealMC (%@)", request.URL.path);
        }
    }
    CHECK([server requestsTo:@"/v2/mods/auth/install"].count == 0, @"no hace falta la sesión de instalación");

    // Si Mojang rechaza el join se sigue con la sesión de instalación, como en Android.
    server.routes[@"POST /session/minecraft/join"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(403, @{@"error": @"ForbiddenOperationException"});
    };
    server.routes[@"POST /v2/mods/auth/install"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"session": @"sesion-instalacion", @"expiresAt": @(Now + 3600)});
    };
    [server.requests removeAllObjects];
    outcome = [TicketClient(server, TempDir()) ticketFor:Account(@"Steve", YES)];
    CHECK(outcome.ticket && [server requestsTo:@"/v2/mods/auth/install"].count == 1, @"join rechazado: ticket por instalación (%@)", outcome.reason);
    CHECK([server requestsTo:@"/v2/mods/auth/verify"].count == 0, @"sin join no se verifica");

    // Una sesión guardada que el servidor ya no acepta se renueva una vez.
    NSString *state = TempDir();
    [TicketClient(server, state) ticketFor:Account(@"Steve", NO)];
    __block int calls = 0;
    server.routes[@"POST /v2/mods/ticket"] = ^RPResponse *(NSURLRequest *r) {
        calls++;
        return calls == 1 ? Reply(401, @{@"error": @"unauthorized"}) : Reply(200, @{@"ticket": TicketSteve});
    };
    [server.requests removeAllObjects];
    outcome = [TicketClient(server, state) ticketFor:Account(@"Steve", NO)];
    CHECK(outcome.ticket && calls == 2 && [server requestsTo:@"/v2/mods/auth/install"].count == 1, @"401 con la sesión guardada: se pide otra y se reintenta");

    // Amethyst deja "offline" como token si no pudo renovar la cuenta: no es premium.
    RPTicketAccount *stale = Account(@"Steve", YES);
    stale.accessToken = @"offline";
    [server.requests removeAllObjects];
    [TicketClient(server, TempDir()) ticketFor:stale];
    CHECK([server requestsTo:@"/v2/mods/auth/challenge"].count == 0, @"con token offline no se intenta el join");
}

#pragma mark - Acceso por invitación (S2)

static RPSession *SessionClient(RPFakeServer *server, RPMemoryStore *store, int64_t now) {
    return [[RPSession alloc] initWithBaseURL:@"https://backend.test" store:store transport:server.transport nowMs:^int64_t(void) {
        return now;
    } deviceName:@"Apple iPhone15,2"];
}

static NSDictionary *SessionReply(int64_t offlineUntil) {
    return @{@"token": @"token-1", @"user": @{@"email": @"ana@ejemplo.com", @"name": @"Ana", @"role": @"user"},
             @"expiresAt": @(offlineUntil + 1000), @"offlineUntil": @(offlineUntil)};
}

static void TestActivate(void) {
    RPFakeServer *server = [RPFakeServer new];
    RPMemoryStore *store = [RPMemoryStore new];
    server.routes[@"POST /v1/activate"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, SessionReply(5000));
    };
    RPSessionState *state = [SessionClient(server, store, 1000) activateEmail:@"  Ana@Ejemplo.com " code:@" abc123 "];
    CHECK(state.access == RPAccessSignedIn, @"la activación abre la sesión (%@)", state.message);
    NSDictionary *sent = BodyOf(server.requests.firstObject);
    CHECK([sent[@"email"] isEqualToString:@"ana@ejemplo.com"] && [sent[@"inviteCode"] isEqualToString:@"abc123"], @"correo y código limpios: %@", sent);
    CHECK([sent[@"appVersion"] isEqualToString:@"ios-1.0.0"] && [sent[@"deviceName"] isEqualToString:@"Apple iPhone15,2"], @"versión y nombre del iPhone");
    NSString *deviceId = sent[@"deviceId"];
    CHECK(deviceId.length >= 16, @"id de dispositivo");
    CHECK(store.items[@"session"] != nil, @"la sesión queda en el llavero");
    [SessionClient(server, store, 1000) activateEmail:@"ana@ejemplo.com" code:@"otro"];
    CHECK([BodyOf(server.requests.lastObject)[@"deviceId"] isEqualToString:deviceId], @"el id de dispositivo no cambia");

    server.routes[@"POST /v1/activate"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(403, @{@"error": @"bad_invite", @"message": @"Código de invitación inválido o caducado."});
    };
    state = [SessionClient(server, [RPMemoryStore new], 1000) activateEmail:@"ana@ejemplo.com" code:@"malo"];
    CHECK(state.access == RPAccessSignedOut && [state.message isEqualToString:@"Código de invitación inválido o caducado."], @"el mensaje del servidor llega tal cual: %@", state.message);

    server.down = YES;
    state = [SessionClient(server, [RPMemoryStore new], 1000) activateEmail:@"ana@ejemplo.com" code:@"x"];
    CHECK([state.message hasPrefix:@"No hay conexión con NationCode"], @"sin red: %@", state.message);

    [server.requests removeAllObjects];
    state = [SessionClient(server, [RPMemoryStore new], 1000) activateEmail:@" " code:@""];
    CHECK([state.message hasPrefix:@"Escribe tu correo"] && server.requests.count == 0, @"campos vacíos no llegan al servidor");
}

static void TestRestore(void) {
    RPFakeServer *server = [RPFakeServer new];
    RPMemoryStore *store = [RPMemoryStore new];
    CHECK([SessionClient(server, store, 1000) restore].access == RPAccessSignedOut && server.requests.count == 0, @"sin sesión no se consulta al servidor");

    server.routes[@"POST /v1/activate"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, SessionReply(5000));
    };
    [SessionClient(server, store, 1000) activateEmail:@"ana@ejemplo.com" code:@"abc"];

    server.routes[@"GET /v1/me"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"user": @{@"email": @"ana@ejemplo.com"}, @"expiresAt": @90000, @"offlineUntil": @80000});
    };
    RPSessionState *state = [SessionClient(server, store, 2000) restore];
    CHECK(state.access == RPAccessSignedIn, @"/v1/me 200 valida la sesión");
    CHECK([[server requestsTo:@"/v1/me"].lastObject valueForHTTPHeaderField:@"Authorization"] != nil, @"con Bearer");

    server.down = YES;
    CHECK([SessionClient(server, store, 79999) restore].access == RPAccessOffline, @"sin red vale hasta offlineUntil (renovado por /v1/me)");
    state = [SessionClient(server, store, 80001) restore];
    CHECK(state.access == RPAccessSignedOut && [state.message hasPrefix:@"Necesitas conexión"], @"pasado offlineUntil hay que conectarse: %@", state.message);
    CHECK(store.items[@"session"] != nil, @"vencer sin conexión no borra la sesión");

    server.down = NO;
    server.routes[@"GET /v1/me"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(403, @{@"error": @"revoked", @"message": @"Tu cuenta o este dispositivo fueron desactivados por NationCode."});
    };
    state = [SessionClient(server, store, 3000) restore];
    CHECK(state.access == RPAccessBlocked && [state.message hasPrefix:@"Tu cuenta o este dispositivo"], @"403 revoked bloquea");
    CHECK(store.items[@"session"] == nil, @"y borra la sesión");
    CHECK(![SessionClient(server, store, 3000) restore].canPlay, @"después no se puede jugar");

    [SessionClient(server, store, 1000) activateEmail:@"ana@ejemplo.com" code:@"abc"];
    server.routes[@"GET /v1/me"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(401, @{@"error": @"unauthorized", @"message": @"Sesión no válida. Vuelve a activar el dispositivo."});
    };
    state = [SessionClient(server, store, 3000) restore];
    CHECK(state.access == RPAccessBlocked && store.items[@"session"] == nil, @"401 también cierra la sesión");

    [SessionClient(server, store, 1000) activateEmail:@"ana@ejemplo.com" code:@"abc"];
    [server.requests removeAllObjects];
    [SessionClient(server, store, 1000) logout];
    NSURLRequest *logout = [server requestsTo:@"/v1/logout"].firstObject;
    CHECK([logout.HTTPMethod isEqualToString:@"POST"] && [[logout valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer token-1"], @"logout avisa al servidor");
    CHECK(store.items[@"session"] == nil, @"y borra la sesión");
}

#pragma mark - Fabric (S4)

static void TestFabric(void) {
    NSString *dir = TempDir();
    NSString *versions = [dir stringByAppendingPathComponent:@"versions"];
    NSString *mods = [dir stringByAppendingPathComponent:@"mods"];
    RPFakeServer *server = [RPFakeServer new];
    server.routes[@"GET /v2/versions/loader/1.21.11"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @[@{@"loader": @{@"version": @"0.17.0-beta", @"stable": @NO}}, @{@"loader": @{@"version": @"0.16.14", @"stable": @YES}}]);
    };
    server.routes[@"GET /v2/versions/loader/1.21.11/0.16.14/profile/json"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"id": @"fabric-loader-0.16.14-1.21.11", @"inheritsFrom": @"1.21.11"});
    };
    RPFabric *fabric = [[RPFabric alloc] initWithTransport:server.transport];
    NSString *error = nil;
    NSString *versionId = [fabric installLoader:@"fabric" mc:@"1.21.11" versionsDir:versions error:&error];
    CHECK([versionId isEqualToString:@"fabric-loader-0.16.14-1.21.11"], @"primer loader estable (%@)", error);
    CHECK([[server.requests.firstObject URL].host isEqualToString:@"meta.fabricmc.net"], @"desde meta.fabricmc.net");
    NSString *profile = [versions stringByAppendingPathComponent:@"fabric-loader-0.16.14-1.21.11/fabric-loader-0.16.14-1.21.11.json"];
    CHECK([ReadText(profile) containsString:@"inheritsFrom"], @"perfil en versions/<id>/<id>.json");

    error = nil;
    CHECK([fabric installLoader:@"neoforge" mc:@"1.21.1" versionsDir:versions error:&error] == nil && [error containsString:@"NeoForge"], @"NeoForge no se ofrece");

    [server.requests removeAllObjects];
    error = nil;
    [fabric installLoader:@"legacy-fabric" mc:@"1.8.9" versionsDir:versions error:&error];
    CHECK([[server.requests.firstObject URL].host isEqualToString:@"meta.legacyfabric.net"], @"1.8.9 desde meta.legacyfabric.net");

    // Sin ningún loader estable se usa el primero de la lista.
    server.routes[@"GET /v2/versions/loader/1.21.10"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @[@{@"loader": @{@"version": @"0.18.0", @"stable": @NO}}]);
    };
    server.routes[@"GET /v2/versions/loader/1.21.10/0.18.0/profile/json"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"id": @"fabric-loader-0.18.0-1.21.10"});
    };
    CHECK([[fabric installLoader:@"fabric" mc:@"1.21.10" versionsDir:versions error:&error] isEqualToString:@"fabric-loader-0.18.0-1.21.10"], @"sin estable: el primero");
    server.routes[@"GET /v2/versions/loader/1.21.9/0.1/profile/json"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @{@"id": @"../fuera"});
    };
    server.routes[@"GET /v2/versions/loader/1.21.9"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @[@{@"loader": @{@"version": @"0.1", @"stable": @YES}}]);
    };
    CHECK([fabric installLoader:@"fabric" mc:@"1.21.9" versionsDir:versions error:&error] == nil, @"un id con carpetas no se escribe");

    NSString *apiFile = [dir stringByAppendingPathComponent:@"api.bin"];
    WriteText(@"fabric api", apiFile);
    NSString *sha1 = [RPCatalog sha1OfFile:apiFile];
    server.routes[@"GET /v2/project/fabric-api/version"] = ^RPResponse *(NSURLRequest *r) {
        return Reply(200, @[
            @{@"version_type": @"beta", @"files": @[]},
            @{@"version_type": @"release", @"files": @[
                @{@"filename": @"fabric-api-0.1.0+1.21.11-sources.jar", @"url": @"https://cdn.modrinth.test/sources.jar", @"primary": @NO, @"hashes": @{@"sha1": sha1}},
                @{@"filename": @"fabric-api-0.1.0+1.21.11.jar", @"url": @"https://cdn.modrinth.test/api.jar", @"primary": @YES, @"hashes": @{@"sha1": sha1}},
            ]},
        ]);
    };
    server.routes[@"GET /api.jar"] = ^RPResponse *(NSURLRequest *r) {
        return [RPResponse status:200 body:[@"fabric api" dataUsingEncoding:NSUTF8StringEncoding]];
    };
    [NSFileManager.defaultManager createDirectoryAtPath:mods withIntermediateDirectories:YES attributes:nil error:nil];
    WriteText(@"vieja", [mods stringByAppendingPathComponent:@"fabric-api-0.0.1+1.20.1.jar"]);
    error = nil;
    CHECK([fabric ensureFabricApi:@"1.21.11" mods:mods error:&error], @"instala Fabric API: %@", error);
    CHECK([ReadText([mods stringByAppendingPathComponent:@"fabric-api-0.1.0+1.21.11.jar"]) isEqualToString:@"fabric api"], @"el archivo primary de la versión release");
    CHECK([NSFileManager.defaultManager fileExistsAtPath:[mods stringByAppendingPathComponent:@"fabric-api-0.0.1+1.20.1.jar.disabled"]], @"la Fabric API de otra versión se desactiva");

    server.down = YES;
    CHECK([fabric ensureFabricApi:@"1.21.11" mods:mods error:&error], @"sin red vale la instalada");
    NSString *empty = [TempDir() stringByAppendingPathComponent:@"mods"];
    error = nil;
    CHECK(![fabric ensureFabricApi:@"1.21.11" mods:empty error:&error] && [error containsString:@"Fabric API"], @"sin red y sin Fabric API no se puede jugar: %@", error);

    server.down = NO;
    server.routes[@"GET /api.jar"] = ^RPResponse *(NSURLRequest *r) {
        return [RPResponse status:200 body:[@"manipulado" dataUsingEncoding:NSUTF8StringEncoding]];
    };
    error = nil;
    CHECK(![fabric ensureFabricApi:@"1.21.11" mods:[TempDir() stringByAppendingPathComponent:@"mods"] error:&error] && [error containsString:@"SHA-1"], @"una descarga que no coincide se rechaza: %@", error);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "uso: rptests <mods-manifest-0.6.6.json>\n");
            return 2;
        }
        TestCatalog(@(argv[1]));
        TestInstallClient();
        TestTicketRules();
        TestTicketFlow();
        TestPremiumTicket();
        TestActivate();
        TestRestore();
        TestFabric();
        printf("RealPhone iOS: %d comprobaciones, %d fallos\n", checks, failures);
        return failures == 0 ? 0 : 1;
    }
}
