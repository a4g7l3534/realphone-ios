#import "RPHTTP.h"

@implementation RPResponse

+ (instancetype)status:(NSInteger)status body:(NSData *)body {
    RPResponse *r = [self new];
    r->_status = status;
    r->_body = body;
    return r;
}

+ (instancetype)failure:(NSError *)error {
    RPResponse *r = [self new];
    r->_error = error;
    return r;
}

- (BOOL)ok {
    return self.status >= 200 && self.status < 300;
}

- (id)parsed {
    if (self.body.length == 0) {
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:self.body options:NSJSONReadingMutableContainers error:nil];
}

- (NSDictionary *)jsonObject {
    id value = [self parsed];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (NSArray *)jsonArray {
    id value = [self parsed];
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

@end

@implementation RPHTTP

+ (NSURLSession *)session {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.URLCache = nil;
        config.HTTPCookieStorage = nil;
        config.HTTPShouldSetCookies = NO;
        config.HTTPAdditionalHeaders = @{@"User-Agent": @"RealPhone-iOS (NationCode)"};
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

+ (RPTransport)system {
    return ^RPResponse *(NSURLRequest *request) {
        if (!request.URL) {
            return [RPResponse failure:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil]];
        }
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        __block RPResponse *result = nil;
        NSURLSessionDataTask *task = [RPHTTP.session dataTaskWithRequest:request
            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (error) {
                result = [RPResponse failure:error];
            } else {
                result = [RPResponse status:((NSHTTPURLResponse *)response).statusCode body:data];
            }
            dispatch_semaphore_signal(done);
        }];
        [task resume];
        // timeoutInterval solo limita el tiempo sin datos; esto limita la petición entera.
        dispatch_time_t limit = dispatch_time(DISPATCH_TIME_NOW, (int64_t)((request.timeoutInterval + 1) * NSEC_PER_SEC));
        if (dispatch_semaphore_wait(done, limit) != 0) {
            [task cancel];
            return [RPResponse failure:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        }
        return result;
    };
}

+ (NSMutableURLRequest *)request:(NSString *)method
                             url:(NSString *)url
                            json:(NSDictionary *)body
                          bearer:(NSString *)bearer
                         timeout:(NSTimeInterval)timeout {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:timeout];
    request.HTTPMethod = method;
    if (body) {
        request.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    }
    if (bearer) {
        [request setValue:[@"Bearer " stringByAppendingString:bearer] forHTTPHeaderField:@"Authorization"];
    }
    return request;
}

+ (NSString *)queryValue:(NSString *)value {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

@end
