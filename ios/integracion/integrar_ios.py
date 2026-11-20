#!/usr/bin/env python3
"""Integra RealPhone en Amethyst-iOS. Es idempotente: una segunda pasada no cambia nada.

Uso: python3 integrar_ios.py <ruta Amethyst-iOS> [--realclient <carpeta con mods-manifest-*.json y jars/>]

Si un texto original del motor no está (otra versión de Amethyst), ese archivo no se toca, se avisa y el
script termina con INTEGRACION_INCOMPLETA y código 1.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
ROOT = os.path.dirname(IOS)
FUENTES = os.path.join(IOS, 'realphone')
MARCA = os.path.join(IOS, 'marca')
REALCLIENT = os.path.join(ROOT, 'engine-src', 'integracion', 'realphone', 'src', 'main', 'assets', 'realclient')
MANIFIESTO = 'mods-manifest-0.6.6.json'
ID_VIEJO = 'org.angelauramc.amethyst'
ID_NUEVO = 'com.nationcode.realphone'

AVISOS = []


def leer(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


def escribir(path, texto):
    with open(path, 'w', encoding='utf-8', newline='') as f:
        f.write(texto)


def editar(motor, rel, cambios):
    """cambios: lista de (etiqueta, hecho, [(original, nuevo)]). Todo el archivo o nada.
    hecho: texto que solo existe con ese cambio aplicado."""
    path = os.path.join(motor, rel)
    original = leer(path)
    nl = '\r\n' if '\r\n' in original else '\n'
    texto = original
    for etiqueta, hecho, pares in cambios:
        if hecho.replace('\n', nl) in texto:
            continue
        pares = [(a.replace('\n', nl), b.replace('\n', nl)) for a, b in pares]
        faltan = [a for a, _ in pares if a not in texto]
        if faltan:
            print('AVISO: %s: no está el texto original "%s"; %s no se modificó'
                  % (etiqueta, faltan[0].strip().splitlines()[0], rel))
            AVISOS.append(etiqueta)
            return
        for a, b in pares:
            texto = texto.replace(a, b, 1)
    if texto != original:
        escribir(path, texto)
        print('editado', rel)


def copiar(origen, destino, motor):
    with open(origen, 'rb') as f:
        datos = f.read()
    if os.path.isfile(destino):
        with open(destino, 'rb') as f:
            if f.read() == datos:
                return
    os.makedirs(os.path.dirname(destino), exist_ok=True)
    with open(destino, 'wb') as f:
        f.write(datos)
    print('copiado', os.path.relpath(destino, motor))


def sincronizar(origenes, carpeta, motor):
    """Deja en carpeta exactamente los archivos de origenes ({nombre: ruta})."""
    os.makedirs(carpeta, exist_ok=True)
    for nombre in os.listdir(carpeta):
        if nombre not in origenes:
            os.remove(os.path.join(carpeta, nombre))
            print('borrado', os.path.relpath(os.path.join(carpeta, nombre), motor))
    for nombre, ruta in sorted(origenes.items()):
        copiar(ruta, os.path.join(carpeta, nombre), motor)


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for bloque in iter(lambda: f.read(1 << 20), b''):
            h.update(bloque)
    return h.hexdigest()


# 1. fuentes Objective-C de RealPhone dentro de Natives/realphone
def fuentes(motor):
    archivos = {n: os.path.join(FUENTES, n) for n in os.listdir(FUENTES) if n.endswith(('.h', '.m'))}
    sincronizar(archivos, os.path.join(motor, 'Natives', 'realphone'), motor)
    return sorted(n for n in archivos if n.endswith('.m'))


# 2. CMake: las fuentes de RealPhone entran en el ejecutable
def cmake(motor, modulos):
    rel = 'Natives/CMakeLists.txt'
    path = os.path.join(motor, rel)
    original = leer(path)
    nl = '\r\n' if '\r\n' in original else '\n'
    bloque = nl + '  # RealPhone' + nl + ''.join('  realphone/%s%s' % (m, nl) for m in modulos)
    sin_bloque = re.sub(re.escape(nl) + r'  # RealPhone' + re.escape(nl) + r'(?:  realphone/\S+' + re.escape(nl) + ')*', '', original)
    ancla = '  utils.m' + nl + ')' + nl
    if ancla not in sin_bloque:
        print('AVISO: CMakeLists: no está el final de la lista de AngelAuraAmethyst ("utils.m"); %s no se modificó' % rel)
        AVISOS.append('CMakeLists fuentes')
        return
    texto = sin_bloque.replace(ancla, '  utils.m' + nl + bloque + ')' + nl, 1)
    if texto != original:
        escribir(path, texto)
        print('editado', rel)


# 3. la pantalla de acceso es la raíz de la ventana
ACCESO_ORIGINAL = '''void launchInitialViewController(UIWindow *window) {
    window.rootViewController = [[LauncherSplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
#if 0
'''
ACCESO_NUEVO = '''void launchInitialViewController(UIWindow *window) {
    // RealPhone: la pantalla de acceso por invitación decide cuándo se abre el launcher
    window.rootViewController = [RPAccessViewController new];
#if 0
'''

# 4. botón Jugar: RealPhone prepara Fabric, RealClient y el ticket antes de que el motor descargue el juego
JUGAR_ORIGINAL = '''    [self setInteractionEnabled:NO forDownloading:YES];

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
'''
JUGAR_NUEVO = '''    if (self.rpBusy) {
        return;
    }
    [self setInteractionEnabled:NO forDownloading:YES];

    // RealPhone: acceso, Fabric, RealClient y ticket de módulos antes de que el motor descargue el juego
    NSString *rpName = self.versionTextField.text;
    if (!self.rpPrepared && [RPLaunch handlesProfile:PLProfiles.current.profiles[rpName]]) {
        self.rpBusy = YES;
        [RPLaunch prepareProfileNamed:rpName status:^(NSString *text) {
            self.progressText.text = text;
        } completion:^(BOOL ok) {
            self.rpBusy = NO;
            // Sin cuenta (se borró mientras se preparaba) launchMinecraft volvería sin reactivar la barra.
            if (!ok || BaseAuthenticator.current == nil) {
                [self setInteractionEnabled:YES forDownloading:YES];
                return;
            }
            self.rpPrepared = YES;
            [self launchMinecraft:sender];
        }];
        return;
    }
    self.rpPrepared = NO;

    NSString *versionId = PLProfiles.current.profiles[self.versionTextField.text][@"lastVersionId"];
'''

# 5. menú lateral: cerrar la sesión de RealPhone
MENU_ANCLA = '    // TODO: Finish log-uploading service integration\n'
MENU_NUEVO = '''    [self.options addObject:
     (id)[LauncherMenuCustomItem
          title:@"Cerrar sesión de RealPhone"
          imageName:@"person.crop.circle.badge.xmark" action:^{
        [RPAccessViewController confirmLogoutFrom:self];
    }]];

'''

# 6. el ticket de RealMC no se escribe en latestlog.txt
LOG_ORIGINAL = '        NSLog(@"[JavaLauncher] Added custom JVM flag: %s", argv[*argc]);\n'
LOG_NUEVO = '''        if ([jvmarg hasPrefix:@"Drealmc.ticket="]) {
            // RealPhone: el ticket de RealMC no se escribe en latestlog.txt
            NSLog(@"[JavaLauncher] Added custom JVM flag: -Drealmc.ticket=<oculto>");
        } else {
            NSLog(@"[JavaLauncher] Added custom JVM flag: %s", argv[*argc]);
        }
'''

PLIST = [
    ('\t<key>CFBundleDisplayName</key>\n\t<string>Amethyst</string>\n',
     '\t<key>CFBundleDisplayName</key>\n\t<string>RealPhone</string>\n'),
    ('\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n' % ID_VIEJO,
     '\t<key>CFBundleIdentifier</key>\n\t<string>%s</string>\n' % ID_NUEVO),
    ('\t<key>CFBundleName</key>\n\t<string>AngelAuraAmethyst</string>\n',
     '\t<key>CFBundleName</key>\n\t<string>RealPhone</string>\n'),
    ('<string>%s.urlscheme</string>' % ID_VIEJO, '<string>%s.urlscheme</string>' % ID_NUEVO),
    ('<string>Angel Aura Amethyst uses the local network to find and communicate with AltServer and LAN servers.</string>',
     '<string>RealPhone usa la red local para encontrar AltServer y los servidores LAN.</string>'),
    ('<string>Angel Aura Amethyst uses the microphone to enable support for voice chat mods.</string>',
     '<string>RealPhone usa el micrófono para los mods de chat de voz.</string>'),
]


def parches(motor):
    editar(motor, 'Natives/ios_uikit_bridge.m', [
        ('ios_uikit_bridge import', '#import "realphone/RPAccessViewController.h"\n',
         [('#include "utils.h"\n', '#include "utils.h"\n#import "realphone/RPAccessViewController.h"\n')]),
        ('ios_uikit_bridge pantalla de acceso', '[RPAccessViewController new]', [(ACCESO_ORIGINAL, ACCESO_NUEVO)]),
    ])
    editar(motor, 'Natives/LauncherNavigationController.m', [
        ('LauncherNavigationController import', '#import "realphone/RPLaunch.h"\n',
         [('#import "utils.h"\n', '#import "utils.h"\n#import "realphone/RPLaunch.h"\n')]),
        ('LauncherNavigationController estado', '@property(nonatomic) BOOL rpPrepared, rpBusy;\n',
         [('@property(nonatomic) int profileSelectedAt;\n',
           '@property(nonatomic) int profileSelectedAt;\n@property(nonatomic) BOOL rpPrepared, rpBusy;\n')]),
        ('LauncherNavigationController perfiles RealClient', '[RPLaunch seedProfiles];',
         [('    [PLProfiles updateCurrent];\n', '    [PLProfiles updateCurrent];\n    [RPLaunch seedProfiles];\n')]),
        ('LauncherNavigationController preparar al jugar', '[RPLaunch prepareProfileNamed:rpName',
         [(JUGAR_ORIGINAL, JUGAR_NUEVO)]),
    ])
    editar(motor, 'Natives/LauncherMenuViewController.m', [
        ('LauncherMenuViewController import', '#import "realphone/RPAccessViewController.h"\n',
         [('#import "utils.h"\n', '#import "utils.h"\n#import "realphone/RPAccessViewController.h"\n')]),
        ('LauncherMenuViewController cerrar sesión', 'confirmLogoutFrom:self', [(MENU_ANCLA, MENU_NUEVO + MENU_ANCLA)]),
    ])
    editar(motor, 'Natives/SurfaceViewController.m', [
        ('SurfaceViewController import', '#import "realphone/RPModulesButton.h"\n',
         [('#include "utils.h"\n', '#include "utils.h"\n#import "realphone/RPModulesButton.h"\n')]),
        ('SurfaceViewController botón de módulos', '[RPModulesButton attachTo:self.view];',
         [('    [self.rootView addSubview:self.inputTextField];\n',
           '    [self.rootView addSubview:self.inputTextField];\n    [RPModulesButton attachTo:self.view];\n')]),
    ])
    editar(motor, 'Natives/JavaLauncher.m', [
        ('JavaLauncher ticket oculto en el log', '-Drealmc.ticket=<oculto>', [(LOG_ORIGINAL, LOG_NUEVO)]),
    ])
    editar(motor, 'Natives/Info.plist', [
        ('Info.plist %d' % i, nuevo, [(viejo, nuevo)]) for i, (viejo, nuevo) in enumerate(PLIST)
    ])
    for nombre in ('entitlements.sideload.xml', 'entitlements.trollstore.xml', 'entitlements.codesign.xml'):
        path = os.path.join(motor, nombre)
        if not os.path.isfile(path):
            continue
        texto = leer(path)
        if ID_VIEJO in texto:
            escribir(path, texto.replace(ID_VIEJO, ID_NUEVO))
            print('editado', nombre)


# 7. iconos y logos de RealPhone (ios/marca, generados con generar_iconos.ps1)
def marca(motor):
    natives = os.path.join(motor, 'Natives')
    assets = os.path.join(natives, 'Assets.xcassets')
    icono = os.path.join(MARCA, 'AppIcon-1024.png')
    destinos = {
        'AppIcon-Light.appiconset/1024x1024.png': icono,
        'AppIcon-Light.appiconset/1024x1024-Transparent.png': os.path.join(MARCA, 'AppIcon-1024-Transparent.png'),
        'AppIcon-Light.appiconset/1024x1024-Monochrome-White.png': os.path.join(MARCA, 'AppIcon-1024-Mono.png'),
        'AppIcon-Dark.appiconset/AppIcon-Dark_1024x1024.png': icono,
        'AppIcon-Development.appiconset/AppIcon-Development_1024x1024.png': icono,
    }
    for rel, origen in destinos.items():
        destino = os.path.join(assets, rel)
        if not os.path.isfile(destino):
            print('AVISO: marca: falta %s en Assets.xcassets' % rel)
            AVISOS.append('marca ' + rel)
            continue
        copiar(origen, destino, motor)

    recursos = os.path.join(natives, 'resources')
    for nombre in os.listdir(recursos):
        if nombre.startswith('AppIcon') and nombre.endswith('60x60@2x.png'):
            copiar(os.path.join(MARCA, 'AppIcon-120.png'), os.path.join(recursos, nombre), motor)
        elif nombre.startswith('AppIcon') and nombre.endswith('76x76@2x~ipad.png'):
            copiar(os.path.join(MARCA, 'AppIcon-152.png'), os.path.join(recursos, nombre), motor)
    copiar(os.path.join(MARCA, 'RPCrown@3x.png'), os.path.join(recursos, 'RPCrown@3x.png'), motor)

    logo = os.path.join(assets, 'AppLogo.imageset')
    copiar(os.path.join(MARCA, 'AppLogo@3x.png'), os.path.join(logo, 'AppLogo@3x.png'), motor)
    contenido = json.dumps({'images': [{'idiom': 'universal', 'filename': 'AppLogo@3x.png', 'scale': '3x'}],
                            'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n'
    path = os.path.join(logo, 'Contents.json')
    if leer(path) != contenido:
        escribir(path, contenido)
        print('editado', os.path.relpath(path, motor))


# 8. catálogo y jars de RealClient: solo entran los que coinciden con el SHA-256 del índice firmado
def realclient(motor, carpeta):
    manifiesto = os.path.join(carpeta, MANIFIESTO)
    with open(manifiesto, encoding='utf-8') as f:
        mods = json.load(f)['mods']
    candidatos = [m for m in mods if 'neoforge' not in m.get('file', '') and m.get('loader') != 'neoforge']
    validos = {}
    for m in candidatos:
        nombre = m.get('file', '')
        jar = os.path.join(carpeta, 'jars', nombre)
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.+_-]*\.jar', nombre) or not re.fullmatch(r'[0-9a-f]{64}', m.get('sha256', '')):
            print('AVISO: RealClient: entrada inválida en el catálogo: %r' % nombre)
            continue
        if not os.path.isfile(jar):
            print('  falta', nombre)
        elif sha256(jar) != m['sha256']:
            print('  NO COINCIDE con el catálogo (no se incluye):', nombre)
        else:
            validos[nombre] = jar
    destino = os.path.join(motor, 'Natives', 'resources', 'realclient')
    sincronizar(validos, os.path.join(destino, 'jars'), motor)
    copiar(manifiesto, os.path.join(destino, MANIFIESTO), motor)
    print('RealClient: %d de %d versiones Fabric con jar verificado' % (len(validos), len(candidatos)))
    if not validos:
        print('AVISO: RealClient: ningún jar coincide con el catálogo; la app no tendría versiones para jugar')
        AVISOS.append('RealClient sin jars')


def main():
    parser = argparse.ArgumentParser(description='Integra RealPhone en Amethyst-iOS')
    parser.add_argument('motor')
    parser.add_argument('--realclient', default=REALCLIENT)
    args = parser.parse_args()
    motor = os.path.abspath(args.motor)
    if not os.path.isfile(os.path.join(motor, 'Natives', 'CMakeLists.txt')):
        print('INTEGRACION_INCOMPLETA: %s no es un checkout de Amethyst-iOS' % motor)
        sys.exit(1)

    cmake(motor, fuentes(motor))
    parches(motor)
    marca(motor)
    realclient(motor, args.realclient)

    if AVISOS:
        print('INTEGRACION_INCOMPLETA: %d cambio(s) sin aplicar: %s' % (len(AVISOS), '; '.join(AVISOS)))
        sys.exit(1)
    print('INTEGRACION_OK')


if __name__ == '__main__':
    main()
