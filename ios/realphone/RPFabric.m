#import "RPCatalog.h"
#import "RPFabric.h"
#import "RPMods.h"

@interface RPFabric ()
@property(nonatomic, copy) RPTransport transport;
@end

@implementation RPFabric

- (instancetype)initWithTransport:(RPTransport)transport {
    self = [super init];
    _transport = [transport copy];
    return self;
}

- (RPResponse *)get:(NSString *)url timeout:(NSTimeInterval)timeout {
    return self.transport([RPHTTP request:@"GET" url:url json:nil bearer:nil timeout:timeout]);
}

static NSString *RPFailureReason(RPResponse *response) {
    if (response.status == 0) {
        return @"sin conexión a internet";
    }
    if (!response.ok) {
        return [NSString stringWithFormat:@"el servidor respondió HTTP %ld", (long)response.status];
    }
    return @"el servidor respondió algo que no se entiende";
}

static BOOL RPFlag(id value, BOOL fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

#pragma mark - Loader

- (NSString *)installLoader:(NSString *)loader mc:(NSString *)mc versionsDir:(NSString *)versions error:(NSString **)error {
    NSString *meta;
    NSString *label;
    if ([loader isEqualToString:@"fabric"]) {
        meta = @"https://meta.fabricmc.net/v2";
        label = @"Fabric";
    } else if ([loader isEqualToString:@"legacy-fabric"]) {
        meta = @"https://meta.legacyfabric.net/v2";
        label = @"Legacy Fabric";
    } else {
        if (error) *error = @"NeoForge todavía no está disponible en RealPhone. Elige una versión Fabric.";
        return nil;
    }

    NSString *base = [NSString stringWithFormat:@"%@/versions/loader/%@", meta, [RPHTTP queryValue:mc]];
    RPResponse *list = [self get:base timeout:15];
    NSArray *loaders = list.ok ? list.jsonArray : nil;
    if (!loaders) {
        if (error) *error = [NSString stringWithFormat:@"No se pudo consultar %@ para Minecraft %@: %@.", label, mc, RPFailureReason(list)];
        return nil;
    }

    NSString *first = nil;
    NSString *stable = nil;
    for (id item in loaders) {
        NSDictionary *info = [item isKindOfClass:NSDictionary.class] ? item[@"loader"] : nil;
        if (![info isKindOfClass:NSDictionary.class] || ![info[@"version"] isKindOfClass:NSString.class]) {
            continue;
        }
        first = first ?: info[@"version"];
        if (RPFlag(info[@"stable"], YES)) {
            stable = info[@"version"];
            break;
        }
    }
    NSString *version = stable ?: first;
    if (!version) {
        if (error) *error = [NSString stringWithFormat:@"No hay %@ publicado para Minecraft %@.", label, mc];
        return nil;
    }

    RPResponse *profile = [self get:[NSString stringWithFormat:@"%@/%@/profile/json", base, [RPHTTP queryValue:version]] timeout:15];
    NSString *versionId = profile.ok ? profile.jsonObject[@"id"] : nil;
    if (![RPCatalog isPlainFileName:versionId]) {
        if (error) *error = [NSString stringWithFormat:@"No se pudo descargar el perfil de %@ para Minecraft %@: %@.", label, mc, RPFailureReason(profile)];
        return nil;
    }

    NSString *dir = [versions stringByAppendingPathComponent:versionId];
    NSError *ioError = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&ioError] ||
        ![profile.body writeToFile:[dir stringByAppendingPathComponent:[versionId stringByAppendingPathExtension:@"json"]]
                           options:NSDataWritingAtomic error:&ioError]) {
        if (error) *error = [NSString stringWithFormat:@"No se pudo guardar el perfil de %@: %@.", label, ioError.localizedDescription];
        return nil;
    }
    return versionId;
}

#pragma mark - Fabric API

- (BOOL)ensureFabricApi:(NSString *)mc mods:(NSString *)mods error:(NSString **)error {
    [NSFileManager.defaultManager createDirectoryAtPath:mods withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *reason = nil;
    if ([self installFabricApi:mc mods:mods reason:&reason]) {
        return YES;
    }
    if ([self hasActiveFabricApi:mods]) {
        NSLog(@"[RealPhone] Fabric API sin actualizar (%@); se usa la instalada", reason);
        return YES;
    }
    if (error) *error = [NSString stringWithFormat:@"No se pudo instalar Fabric API, que RealClient necesita: %@.", reason];
    return NO;
}

- (BOOL)hasActiveFabricApi:(NSString *)mods {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:mods error:nil]) {
        if ([name hasPrefix:@"fabric-api-"] && [name hasSuffix:@".jar"]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)installFabricApi:(NSString *)mc mods:(NSString *)mods reason:(NSString **)reason {
    NSString *url = [NSString stringWithFormat:@"https://api.modrinth.com/v2/project/fabric-api/version?game_versions=%@&loaders=%@",
        [RPHTTP queryValue:[NSString stringWithFormat:@"[\"%@\"]", mc]], [RPHTTP queryValue:@"[\"fabric\"]"]];
    RPResponse *listing = [self get:url timeout:15];
    NSArray *versions = listing.ok ? listing.jsonArray : nil;
    if (!versions) {
        *reason = RPFailureReason(listing);
        return NO;
    }
    if (versions.count == 0) {
        *reason = [NSString stringWithFormat:@"no hay Fabric API publicada para Minecraft %@", mc];
        return NO;
    }

    NSDictionary *chosen = nil;
    for (id version in versions) {
        if ([version isKindOfClass:NSDictionary.class] && [version[@"version_type"] isEqual:@"release"]) {
            chosen = version;
            break;
        }
    }
    if (!chosen && [versions.firstObject isKindOfClass:NSDictionary.class]) {
        chosen = versions.firstObject;
    }
    NSArray *files = [chosen[@"files"] isKindOfClass:NSArray.class] ? chosen[@"files"] : @[];
    NSDictionary *file = nil;
    for (id candidate in files) {
        if (![candidate isKindOfClass:NSDictionary.class]) {
            continue;
        }
        file = file ?: candidate;
        if (RPFlag(candidate[@"primary"], NO)) {
            file = candidate;
            break;
        }
    }

    NSString *name = file[@"filename"];
    NSString *link = file[@"url"];
    NSDictionary *hashes = [file[@"hashes"] isKindOfClass:NSDictionary.class] ? file[@"hashes"] : @{};
    NSString *sha1 = hashes[@"sha1"];
    if (![RPCatalog isPlainFileName:name] || ![name hasPrefix:@"fabric-api-"] || ![name hasSuffix:@".jar"] ||
        ![link isKindOfClass:NSString.class] || ![link hasPrefix:@"https://"] || ![RPCatalog isHex:sha1 length:40]) {
        *reason = @"Modrinth respondió un archivo que no se reconoce";
        return NO;
    }

    NSFileManager *fm = NSFileManager.defaultManager;
    [RPMods disableJarsWithPrefix:@"fabric-api-" inMods:mods keeping:name];
    NSString *dest = [mods stringByAppendingPathComponent:name];
    NSString *disabled = [dest stringByAppendingString:@".disabled"];
    if (![fm fileExistsAtPath:dest] && [fm fileExistsAtPath:disabled]) {
        [fm moveItemAtPath:disabled toPath:dest error:nil];
    }
    if ([[RPCatalog sha1OfFile:dest] isEqualToString:sha1]) {
        return YES;
    }

    RPResponse *jar = [self get:link timeout:60];
    if (!jar.ok || jar.body.length == 0) {
        *reason = RPFailureReason(jar);
        return NO;
    }
    NSString *tmp = [dest stringByAppendingString:@".tmp"];
    if (![jar.body writeToFile:tmp options:NSDataWritingAtomic error:nil]) {
        *reason = @"no se pudo escribir en la carpeta mods";
        return NO;
    }
    if (![[RPCatalog sha1OfFile:tmp] isEqualToString:sha1]) {
        [fm removeItemAtPath:tmp error:nil];
        *reason = @"la descarga no coincide con el SHA-1 que publica Modrinth";
        return NO;
    }
    if (![RPMods replace:dest with:tmp]) {
        [fm removeItemAtPath:tmp error:nil];
        *reason = @"no se pudo escribir en la carpeta mods";
        return NO;
    }
    return YES;
}

@end
