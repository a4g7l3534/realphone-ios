#pragma once
#import <UIKit/UIKit.h>

// Paleta de RealPhone Android (ui/theme/Theme.kt, objeto RP).
static inline UIColor *RPHex(uint32_t rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0 green:((rgb >> 8) & 0xFF) / 255.0 blue:(rgb & 0xFF) / 255.0 alpha:1];
}

static inline UIColor *RPBlack(void) { return RPHex(0x050706); }
static inline UIColor *RPPanel(void) { return RPHex(0x111714); }
static inline UIColor *RPStroke(void) { return RPHex(0x222D27); }
static inline UIColor *RPEmerald(void) { return RPHex(0x10B981); }
static inline UIColor *RPOnEmerald(void) { return RPHex(0x02140D); }
static inline UIColor *RPText(void) { return RPHex(0xE6EEE9); }
static inline UIColor *RPTextDim(void) { return RPHex(0x8A9A92); }
static inline UIColor *RPTextFaint(void) { return RPHex(0x5B6A63); }
static inline UIColor *RPDanger(void) { return RPHex(0xEF4444); }
