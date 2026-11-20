#import <CommonCrypto/CommonDigest.h>
#import "RPCatalog.h"

@interface RPModEntry ()
- (instancetype)initWithFile:(NSString *)file
                   minecraft:(NSString *)minecraft
                      sha256:(NSString *)sha256
                      loader:(NSString *)loader
                        java:(NSInteger)java;
@end

@implementation RPModEntry

- (instancetype)initWithFile:(NSString *)file
                   minecraft:(NSString *)minecraft
                      sha256:(NSString *)sha256
                      loader:(NSString *)loader
                        java:(NSInteger)java {
    self = [super init];
    _file = [file copy];
    _minecraft = [minecraft copy];
    _sha256 = [sha256 copy];
    _loader = [loader copy];
    _java = java;
    return self;
}

@end

@implementation RPCatalog

+ (NSArray<RPModEntry *> *)entriesFromData:(NSData *)data error:(NSString **)error {
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *mods = [root isKindOfClass:NSDictionary.class] ? root[@"mods"] : nil;
    if (![mods isKindOfClass:NSArray.class]) {
        if (error) *error = @"El catálogo de RealClient no es un JSON con la lista \"mods\".";
        return nil;
    }

    NSMutableArray<RPModEntry *> *entries = [NSMutableArray arrayWithCapacity:mods.count];
    for (id mod in mods) {
        NSDictionary *m = [mod isKindOfClass:NSDictionary.class] ? mod : @{};
        NSString *file = m[@"file"];
        NSArray *versions = [m[@"minecraft"] isKindOfClass:NSArray.class] ? m[@"minecraft"] : @[];
        NSString *minecraft = versions.firstObject;
        if (![self isPlainFileName:file] || ![self isVersionName:minecraft] || ![self isHex:m[@"sha256"] length:64]) {
            if (error) *error = [NSString stringWithFormat:@"Entrada inválida en el catálogo de RealClient: %@", file ?: @"(sin archivo)"];
            return nil;
        }

        NSString *loader = [m[@"loader"] isKindOfClass:NSString.class] ? m[@"loader"] : nil;
        if (!loader) {
            if ([file rangeOfString:@"neoforge"].location != NSNotFound) {
                loader = @"neoforge";
            } else if ([versions containsObject:@"1.8.9"]) {
                loader = @"legacy-fabric";
            } else {
                loader = @"fabric";
            }
        }
        NSInteger java = [m[@"java"] isKindOfClass:NSNumber.class] ? [m[@"java"] integerValue] : 0;
        [entries addObject:[[RPModEntry alloc] initWithFile:file minecraft:minecraft sha256:m[@"sha256"] loader:loader java:java]];
    }
    return entries;
}

// Modrinth solo publica SHA-1 para sus archivos: hace falta aunque CommonCrypto lo marque como obsoleto.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
+ (NSString *)digestOfFile:(NSString *)path sha1:(BOOL)sha1 {
    NSInputStream *input = [NSInputStream inputStreamWithFileAtPath:path];
    [input open];
    if (input.streamStatus != NSStreamStatusOpen) {
        [input close];
        return nil;
    }

    CC_SHA1_CTX ctx1;
    CC_SHA256_CTX ctx256;
    if (sha1) {
        CC_SHA1_Init(&ctx1);
    } else {
        CC_SHA256_Init(&ctx256);
    }
    const NSUInteger chunk = 1 << 20;
    uint8_t *buffer = malloc(chunk);
    NSInteger read;
    while ((read = [input read:buffer maxLength:chunk]) > 0) {
        if (sha1) {
            CC_SHA1_Update(&ctx1, buffer, (CC_LONG)read);
        } else {
            CC_SHA256_Update(&ctx256, buffer, (CC_LONG)read);
        }
    }
    free(buffer);
    [input close];
    if (read < 0) {
        return nil;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (sha1) {
        CC_SHA1_Final(digest, &ctx1);
        return [self hex:[NSData dataWithBytes:digest length:CC_SHA1_DIGEST_LENGTH]];
    }
    CC_SHA256_Final(digest, &ctx256);
    return [self hex:[NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH]];
}
#pragma clang diagnostic pop

+ (NSString *)sha256OfFile:(NSString *)path {
    return [self digestOfFile:path sha1:NO];
}

+ (NSString *)sha1OfFile:(NSString *)path {
    return [self digestOfFile:path sha1:YES];
}

+ (NSString *)sha256Hex:(NSData *)data {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return [self hex:[NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH]];
}

+ (NSString *)hex:(NSData *)data {
    const unsigned char *bytes = data.bytes;
    NSMutableString *text = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [text appendFormat:@"%02x", bytes[i]];
    }
    return text;
}

+ (BOOL)isHex:(id)value length:(NSUInteger)length {
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *text = value;
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"].invertedSet;
    return text.length == length && [text rangeOfCharacterFromSet:other].location == NSNotFound;
}

+ (BOOL)isVersionName:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *text = value;
    NSCharacterSet *other = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"].invertedSet;
    return text.length <= 32 && [text rangeOfCharacterFromSet:other].location == NSNotFound && [self isPlainFileName:text];
}

+ (NSComparisonResult)compareVersion:(NSString *)a to:(NSString *)b {
    NSArray<NSString *> *x = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *y = [b componentsSeparatedByString:@"."];
    for (NSUInteger i = 0; i < MAX(x.count, y.count); i++) {
        NSInteger p = i < x.count ? x[i].integerValue : 0;
        NSInteger q = i < y.count ? y[i].integerValue : 0;
        if (p != q) {
            return p < q ? NSOrderedAscending : NSOrderedDescending;
        }
    }
    return NSOrderedSame;
}

+ (BOOL)isPlainFileName:(id)value {
    if (![value isKindOfClass:NSString.class]) {
        return NO;
    }
    NSString *name = value;
    NSMutableCharacterSet *bad = [NSCharacterSet.controlCharacterSet mutableCopy];
    [bad addCharactersInString:@"/\\:"];
    return name.length > 0 && name.length <= 255
        && [name rangeOfCharacterFromSet:bad].location == NSNotFound
        && ![name hasPrefix:@"."];
}

@end
