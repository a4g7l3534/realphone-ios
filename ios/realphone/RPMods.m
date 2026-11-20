#import "RPMods.h"

@implementation RPMods

+ (BOOL)installClient:(RPModEntry *)entry from:(NSString *)source intoMods:(NSString *)mods error:(NSString **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *ioError = nil;
    if (![fm createDirectoryAtPath:mods withIntermediateDirectories:YES attributes:nil error:&ioError]) {
        if (error) *error = [NSString stringWithFormat:@"no se pudo crear la carpeta mods (%@)", ioError.localizedDescription];
        return NO;
    }
    [self disableJarsWithPrefix:@"realmc-client" inMods:mods keeping:entry.file];

    if (![fm fileExistsAtPath:source]) {
        [self disableJarsWithPrefix:@"realmc-client" inMods:mods keeping:nil];
        if (error) *error = [NSString stringWithFormat:@"esta copia de RealPhone no trae RealClient para Minecraft %@", entry.minecraft];
        return NO;
    }
    if (![[RPCatalog sha256OfFile:source] isEqualToString:entry.sha256]) {
        [self disableJarsWithPrefix:@"realmc-client" inMods:mods keeping:nil];
        if (error) *error = [NSString stringWithFormat:@"el RealClient de Minecraft %@ no coincide con el catálogo firmado", entry.minecraft];
        return NO;
    }

    NSString *dest = [mods stringByAppendingPathComponent:entry.file];
    if ([[RPCatalog sha256OfFile:dest] isEqualToString:entry.sha256]) {
        return YES;
    }
    NSString *tmp = [dest stringByAppendingString:@".tmp"];
    [fm removeItemAtPath:tmp error:nil];
    if (![fm copyItemAtPath:source toPath:tmp error:&ioError] || ![self replace:dest with:tmp]) {
        [fm removeItemAtPath:tmp error:nil];
        if (error) *error = [NSString stringWithFormat:@"no se pudo copiar RealClient a mods (%@)", ioError.localizedDescription ?: @"error de archivo"];
        return NO;
    }
    return YES;
}

+ (void)disableJarsWithPrefix:(NSString *)prefix inMods:(NSString *)mods keeping:(NSString *)keep {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *name in [fm contentsOfDirectoryAtPath:mods error:nil]) {
        if (![name hasPrefix:prefix] || ![name hasSuffix:@".jar"] || [name isEqualToString:keep]) {
            continue;
        }
        NSString *path = [mods stringByAppendingPathComponent:name];
        NSString *disabled = [path stringByAppendingString:@".disabled"];
        [fm removeItemAtPath:disabled error:nil];
        NSError *ioError = nil;
        if (![fm moveItemAtPath:path toPath:disabled error:&ioError]) {
            NSLog(@"[RealPhone] No se pudo desactivar %@: %@", name, ioError.localizedDescription);
        }
    }
}

+ (BOOL)replace:(NSString *)dest with:(NSString *)tmp {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:dest]) {
        return [fm replaceItemAtURL:[NSURL fileURLWithPath:dest] withItemAtURL:[NSURL fileURLWithPath:tmp]
                     backupItemName:nil options:0 resultingItemURL:nil error:nil];
    }
    return [fm moveItemAtPath:tmp toPath:dest error:nil];
}

@end
