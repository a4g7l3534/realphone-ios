#import "RPAccessViewController.h"
#import "RPCatalog.h"
#import "RPConfig.h"
#import "RPFabric.h"
#import "RPLaunch.h"
#import "RPMods.h"
#import "RPSession.h"
#import "RPTicket.h"
#import "../authenticator/BaseAuthenticator.h"
#import "../LauncherPreferences.h"
#import "../PLProfiles.h"
#import "../ios_uikit_bridge.h"
#include "../utils.h"

// Claves propias dentro del perfil; Amethyst guarda y conserva las que no conoce.
static NSString *const RPKeyMinecraft = @"realphoneMinecraft";
static NSString *const RPKeyLoader = @"realphoneLoader";
// Los argumentos de Java (sin ticket) que RealPhone escribió la última vez, para saber si el usuario los cambió
static NSString *const RPKeyWrittenArgs = @"realphoneJavaArgs";
static NSString *const RPTicketFlag = @"-Drealmc.ticket=";

@implementation RPLaunch

#pragma mark - Catálogo

+ (NSString *)bundleDir {
    return [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"realclient"];
}

+ (NSString *)jarFor:(RPModEntry *)entry {
    return [[self.bundleDir stringByAppendingPathComponent:@"jars"] stringByAppendingPathComponent:entry.file];
}

// Las builds Fabric y Legacy Fabric cuyo jar viene dentro de la app, de la versión más nueva a la más vieja.
+ (NSArray<RPModEntry *> *)playable {
    static NSArray<RPModEntry *> *playable;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [self.bundleDir stringByAppendingPathComponent:[RP_MANIFEST_NAME stringByAppendingPathExtension:@"json"]];
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSString *error = nil;
        NSArray<RPModEntry *> *entries = data ? [RPCatalog entriesFromData:data error:&error] : nil;
        if (!entries) {
            NSLog(@"[RealPhone] Catálogo de RealClient no disponible: %@", error ?: @"falta el archivo");
            playable = @[];
            return;
        }
        NSMutableArray<RPModEntry *> *list = [NSMutableArray new];
        for (RPModEntry *entry in entries) {
            if (![entry.loader isEqualToString:@"neoforge"] && [NSFileManager.defaultManager fileExistsAtPath:[self jarFor:entry]]) {
                [list addObject:entry];
            }
        }
        [list sortUsingComparator:^NSComparisonResult(RPModEntry *a, RPModEntry *b) {
            return [RPCatalog compareVersion:b.minecraft to:a.minecraft];
        }];
        playable = list;
    });
    return playable;
}

+ (NSString *)profileNameFor:(RPModEntry *)entry {
    return [@"RealClient " stringByAppendingString:entry.minecraft];
}

+ (RPModEntry *)entryForProfile:(NSDictionary *)profile {
    NSString *minecraft = profile[RPKeyMinecraft];
    NSString *loader = profile[RPKeyLoader];
    if (![minecraft isKindOfClass:NSString.class]) {
        return nil;
    }
    for (RPModEntry *entry in self.playable) {
        if ([entry.minecraft isEqualToString:minecraft] && (![loader isKindOfClass:NSString.class] || [entry.loader isEqualToString:loader])) {
            return entry;
        }
    }
    return nil;
}

+ (BOOL)handlesProfile:(NSDictionary *)profile {
    return [profile isKindOfClass:NSDictionary.class] && [self entryForProfile:profile] != nil;
}

#pragma mark - Perfiles

+ (void)seedProfiles {
    PLProfiles *profiles = PLProfiles.current;
    NSMutableDictionary *all = profiles.profileDict[@"profiles"];
    if (![all isKindOfClass:NSMutableDictionary.class]) {
        // Los perfiles por defecto de Amethyst se crean inmutables hasta que se vuelven a leer del archivo.
        all = [all isKindOfClass:NSDictionary.class] ? [all mutableCopy] : [NSMutableDictionary new];
        profiles.profileDict[@"profiles"] = (id)all;
    }

    BOOL firstTime = YES;
    BOOL changed = NO;
    for (NSString *key in all.allKeys) {
        NSDictionary *profile = all[key];
        if (![profile isKindOfClass:NSDictionary.class] || !profile[RPKeyMinecraft]) {
            continue;
        }
        firstTime = NO;
        // El ticket solo hace falta entre Jugar y el arranque de Java: no se deja guardado en el perfil.
        NSString *args = profile[@"javaArgs"];
        if ([args isKindOfClass:NSString.class] && [args containsString:RPTicketFlag]) {
            NSMutableDictionary *clean = [profile mutableCopy];
            clean[@"javaArgs"] = [self withoutTicket:args];
            all[key] = clean;
            changed = YES;
        }
    }

    for (RPModEntry *entry in self.playable) {
        NSString *name = [self profileNameFor:entry];
        if (all[name]) {
            continue;
        }
        all[name] = @{
            @"name": name,
            @"lastVersionId": entry.minecraft,
            @"gameDir": [NSString stringWithFormat:@"./realphone/%@-%@", entry.loader, entry.minecraft],
            RPKeyMinecraft: entry.minecraft,
            RPKeyLoader: entry.loader,
        }.mutableCopy;
        changed = YES;
    }

    NSString *selected = profiles.selectedProfileName;
    if (firstTime && self.playable.count > 0 && (!all[selected] || [selected isEqualToString:@"(Default)"])) {
        profiles.profileDict[@"selectedProfile"] = (id)[self profileNameFor:self.playable.firstObject];
        changed = YES;
    }
    if (changed) {
        [profiles save];
    }
}

+ (NSString *)instanceDirFor:(NSDictionary *)profile {
    NSString *gameDir = profile[@"gameDir"];
    if (![gameDir isKindOfClass:NSString.class] || gameDir.length == 0) {
        gameDir = @".";
    }
    // La misma ruta que arma JavaLauncher.m para -Duser.dir
    return [NSString stringWithFormat:@"%s/instances/%@/%@", getenv("AME_HOME"),
        getPrefObject(@"general.game_directory"), gameDir].stringByStandardizingPath;
}

+ (NSString *)stateDir {
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    return [support stringByAppendingPathComponent:@"com.nationcode.realphone/presence"];
}

#pragma mark - Cuenta y argumentos de Java

// Se lee en el hilo principal: BaseAuthenticator no es seguro entre hilos.
+ (RPTicketAccount *)ticketAccount {
    BaseAuthenticator *auth = BaseAuthenticator.current;
    NSDictionary *data = auth.authData;
    RPTicketAccount *account = [RPTicketAccount new];
    account.name = [data[@"username"] isKindOfClass:NSString.class] ? data[@"username"] : @"";
    NSString *profileId = [data[@"profileId"] isKindOfClass:NSString.class] ? data[@"profileId"] : @"";
    account.uuid = [profileId stringByReplacingOccurrencesOfString:@"-" withString:@""].lowercaseString;

    NSString *xuid = data[@"xuid"];
    if ([auth isKindOfClass:MicrosoftAuthenticator.class] && [xuid isKindOfClass:NSString.class]) {
        NSString *token = [MicrosoftAuthenticator tokenDataOfProfile:xuid][@"accessToken"];
        account.accessToken = [token isKindOfClass:NSString.class] ? token : nil;
    }
    BOOL demo = [account.name hasPrefix:@"Demo."] || [account.uuid isEqualToString:@"00000000000000000000000000000000"];
    account.premium = account.accessToken.length > 0 && !demo;
    return account;
}

+ (NSString *)withoutTicket:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return @"";
    }
    NSString *args = value;
    NSString *clean = [args stringByReplacingOccurrencesOfString:@"\\s*-Drealmc\\.ticket=\\S*" withString:@""
                                                         options:NSRegularExpressionSearch range:NSMakeRange(0, args.length)];
    return [clean stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}

// Los argumentos de Java propios del perfil si el usuario los cambió en el editor; si el perfil sigue con lo que
// escribió RealPhone, los generales de Ajustes, que pueden haber cambiado desde entonces.
+ (NSString *)baseArgsFor:(NSDictionary *)profile {
    NSString *own = [self withoutTicket:profile[@"javaArgs"]];
    if (own.length > 0 && ![own isEqualToString:[self withoutTicket:profile[RPKeyWrittenArgs]]]) {
        return own;
    }
    return [self withoutTicket:getPrefObject(@"java.java_args")];
}

+ (NSString *)javaArgs:(NSString *)base ticket:(NSString *)ticket {
    if (![RPTicket engineSafe:ticket]) {
        return base;
    }
    NSString *flag = [RPTicketFlag stringByAppendingString:ticket];
    return base.length > 0 ? [NSString stringWithFormat:@"%@ %@", base, flag] : flag;
}

+ (void)writePresenceConfig:(NSString *)instance {
    NSString *dir = [instance stringByAppendingPathComponent:@"config/realmc-client"];
    NSString *path = [dir stringByAppendingPathComponent:@"presence.json"];
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"api": RP_PRESENCE_API, @"assets": RP_PRESENCE_ASSETS}
        options:NSJSONWritingPrettyPrinted | NSJSONWritingWithoutEscapingSlashes error:nil];
    if ([[NSData dataWithContentsOfFile:path] isEqualToData:body]) {
        return;
    }
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error] ||
        ![body writeToFile:path options:NSDataWritingAtomic error:&error]) {
        NSLog(@"[RealPhone] No se pudo escribir presence.json: %@", error.localizedDescription);
    }
}

#pragma mark - Preparar la partida

+ (void)prepareProfileNamed:(NSString *)name
                     status:(void (^)(NSString *text))status
                 completion:(void (^)(BOOL ok))completion {
    NSDictionary *profile = [PLProfiles.current.profiles[name] copy];
    RPModEntry *entry = [self entryForProfile:profile];
    if (!entry) {
        completion(YES);
        return;
    }
    NSString *instance = [self instanceDirFor:profile];
    NSString *versions = [@(getenv("GAME_DIR")) stringByAppendingPathComponent:@"versions"];
    NSString *previousId = profile[@"lastVersionId"];
    NSString *jar = [self jarFor:entry];
    NSString *baseArgs = [self baseArgsFor:profile];
    RPTicketAccount *account = [self ticketAccount];

    void (^say)(NSString *) = ^(NSString *text) {
        dispatch_async(dispatch_get_main_queue(), ^{
            status(text);
        });
    };
    void (^fail)(NSString *) = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            showDialog(@"No se pudo preparar la partida", message);
            completion(NO);
        });
    };

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        say(@"Comprobando tu acceso a RealPhone…");
        RPSessionState *access = [RPSession.shared restore];
        if (!access.canPlay) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO);
                [RPAccessViewController presentGateWithMessage:access.message ?: @"Activa RealPhone en este iPhone para jugar."];
            });
            return;
        }

        BOOL legacy = [entry.loader isEqualToString:@"legacy-fabric"];
        say([NSString stringWithFormat:@"Preparando %@ para Minecraft %@…", legacy ? @"Legacy Fabric" : @"Fabric", entry.minecraft]);
        RPFabric *fabric = [[RPFabric alloc] initWithTransport:RPHTTP.system];
        NSString *error = nil;
        NSString *versionId = [fabric installLoader:entry.loader mc:entry.minecraft versionsDir:versions error:&error];
        if (!versionId) {
            // Sin conexión sirve el perfil que ya se instaló la última vez.
            NSString *previousJson = [NSString stringWithFormat:@"%@/%@/%@.json", versions, previousId, previousId];
            BOOL installed = [RPCatalog isPlainFileName:previousId] && ![previousId isEqualToString:entry.minecraft]
                && [NSFileManager.defaultManager fileExistsAtPath:previousJson];
            if (!installed) {
                fail([error stringByAppendingString:@" La primera vez que juegas una versión necesitas internet."]);
                return;
            }
            NSLog(@"[RealPhone] %@ Se usa el perfil instalado %@", error, previousId);
            versionId = previousId;
        }

        NSString *mods = [instance stringByAppendingPathComponent:@"mods"];
        NSMutableArray<NSString *> *warnings = [NSMutableArray new];
        say(@"Instalando RealClient…");
        if (![RPMods installClient:entry from:jar intoMods:mods error:&error]) {
            [warnings addObject:[NSString stringWithFormat:@"Esta partida abre sin RealClient: %@.", error]];
        }
        if (legacy) {
            // En 1.8.9 una Fabric API moderna hace fallar el arranque.
            [RPMods disableJarsWithPrefix:@"fabric-api-" inMods:mods keeping:nil];
        } else {
            say(@"Comprobando Fabric API…");
            if (![fabric ensureFabricApi:entry.minecraft mods:mods error:&error]) {
                fail(error);
                return;
            }
        }
        [self writePresenceConfig:instance];

        say(@"Pidiendo la licencia de los módulos…");
        RPTicket *tickets = [[RPTicket alloc] initWithAPI:RP_PRESENCE_API stateDir:self.stateDir transport:RPHTTP.system now:^NSTimeInterval(void) {
            return NSDate.date.timeIntervalSince1970;
        }];
        RPTicketOutcome *outcome = [tickets ticketFor:account];
        if (!outcome.ticket) {
            [warnings addObject:[NSString stringWithFormat:@"Los módulos de RealClient quedan apagados en esta partida: %@.", outcome.reason]];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            NSMutableDictionary *live = [PLProfiles.current.profiles[name] mutableCopy];
            if (!live) {
                showDialog(@"No se pudo preparar la partida", @"El perfil se borró mientras se preparaba. Elige otro y pulsa Jugar.");
                completion(NO);
                return;
            }
            live[@"lastVersionId"] = versionId;
            live[@"javaArgs"] = [self javaArgs:baseArgs ticket:outcome.ticket];
            live[RPKeyWrittenArgs] = baseArgs;
            PLProfiles.current.profiles[name] = live;
            [PLProfiles.current save];
            if (warnings.count > 0) {
                showDialog(@"RealPhone", [warnings componentsJoinedByString:@"\n\n"]);
            }
            completion(YES);
        });
    });
}

@end
