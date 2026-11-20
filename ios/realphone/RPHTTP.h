#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Respuesta de una petición. status es 0 si no llegó respuesta (sin red, DNS, tiempo agotado).
@interface RPResponse : NSObject
@property(nonatomic, readonly) NSInteger status;
@property(nonatomic, readonly, nullable) NSData *body;
@property(nonatomic, readonly, nullable) NSError *error;
+ (instancetype)status:(NSInteger)status body:(nullable NSData *)body;
+ (instancetype)failure:(NSError *)error;
- (BOOL)ok;
- (nullable NSDictionary *)jsonObject;
- (nullable NSArray *)jsonArray;
@end

// Bloquea el hilo que llama hasta tener respuesta. Los tests inyectan una falsa.
typedef RPResponse *_Nonnull (^RPTransport)(NSURLRequest *request);

@interface RPHTTP : NSObject
// NSURLSession sin caché ni cookies. Nunca se llama desde el hilo principal.
+ (RPTransport)system;
+ (NSMutableURLRequest *)request:(NSString *)method
                             url:(NSString *)url
                            json:(nullable NSDictionary *)body
                          bearer:(nullable NSString *)bearer
                         timeout:(NSTimeInterval)timeout;
// Codifica un valor para la query (todo lo que no sea letra, número o -._~).
+ (NSString *)queryValue:(NSString *)value;
@end

NS_ASSUME_NONNULL_END
