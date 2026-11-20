#import <Foundation/Foundation.h>
#import "RPHTTP.h"

NS_ASSUME_NONNULL_BEGIN

@interface RPTicketAccount : NSObject
@property(nonatomic, copy) NSString *name;
// UUID sin guiones
@property(nonatomic, copy) NSString *uuid;
// Solo va a sessionserver.mojang.com, nunca a RealMC
@property(nonatomic, copy, nullable) NSString *accessToken;
@property(nonatomic) BOOL premium;
@end

@interface RPTicketOutcome : NSObject
// nil: el juego abre con los módulos apagados
@property(nonatomic, copy, nullable) NSString *ticket;
// Por qué no hay ticket, o por qué se usó el guardado
@property(nonatomic, copy, nullable) NSString *reason;
@end

// Ticket de inicio del mod RealClient (-Drealmc.ticket=...), mismo flujo que RealClientTicket.kt:
//  - premium: /v2/mods/auth/challenge, join de Mojang y /v2/mods/auth/verify
//  - sin premium, o si falla lo anterior: /v2/mods/auth/install con el id de instalación de este iPhone
//  - con esa sesión: /v2/mods/ticket
// Nunca escribe en el log el ticket, la sesión, el token de acceso ni el secreto.
@interface RPTicket : NSObject
- (instancetype)initWithAPI:(NSString *)api
                   stateDir:(NSString *)stateDir
                  transport:(RPTransport)transport
                        now:(NSTimeInterval (^)(void))now;
// Bloquea como mucho unos 10 s. Nunca falla: si no hay ticket lo dice en reason.
- (RPTicketOutcome *)ticketFor:(RPTicketAccount *)account;

// exp del ticket si tiene la forma <payload>.<firma de 64 bytes> en base64url sin relleno y es para name.
+ (nullable NSNumber *)expiryOfTicket:(nullable NSString *)ticket name:(NSString *)name;
// Solo [A-Za-z0-9_.-] y sin los prefijos por los que el motor parte los argumentos de Java.
+ (BOOL)engineSafe:(nullable NSString *)ticket;
+ (NSString *)joinIdForNonce:(NSString *)nonce uuid:(NSString *)uuid;
+ (NSString *)proofForSecret:(NSData *)secret;
@end

NS_ASSUME_NONNULL_END
