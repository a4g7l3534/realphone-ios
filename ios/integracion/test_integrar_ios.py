"""Pruebas de integrar_ios.py contra el Amethyst-iOS fijado en ios/motor/Amethyst-iOS.
Uso: python -m unittest discover -s ios/integracion -v"""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
IOS = os.path.dirname(HERE)
MOTOR = os.path.join(IOS, 'motor', 'Amethyst-iOS')
SCRIPT = os.path.join(HERE, 'integrar_ios.py')
FUENTES = os.path.join(IOS, 'realphone')

# Texto que solo existe con cada cambio aplicado
CAMBIOS = {
    'Natives/CMakeLists.txt': '  realphone/RPLaunch.m\n',
    'Natives/ios_uikit_bridge.m': 'window.rootViewController = [RPAccessViewController new];',
    'Natives/LauncherNavigationController.m': '[RPLaunch prepareProfileNamed:rpName',
    'Natives/LauncherMenuViewController.m': '[RPAccessViewController confirmLogoutFrom:self];',
    'Natives/SurfaceViewController.m': '[RPModulesButton attachTo:self.view];',
    'Natives/JavaLauncher.m': '-Drealmc.ticket=<oculto>',
    'Natives/Info.plist': '<string>com.nationcode.realphone</string>',
}


def leer(path):
    with open(path, encoding='utf-8', newline='') as f:
        return f.read()


class IntegrarIOS(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not os.path.isdir(os.path.join(MOTOR, 'Natives')):
            raise unittest.SkipTest('falta ios/motor/Amethyst-iOS (git clone del motor fijado)')

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix='rp-ios-')
        self.motor = os.path.join(self.tmp, 'Amethyst-iOS')
        shutil.copytree(MOTOR, self.motor, ignore=shutil.ignore_patterns('.git', 'depends', 'artifacts', 'build'))
        self.realclient = os.path.join(self.tmp, 'realclient')
        self.bueno = b'jar de RealClient 1.21.11'
        self.crear_realclient([
            ('realmc-client-0.6.6+mc1.21.11.jar', '1.21.11', self.bueno, self.bueno),
            ('realmc-client-0.6.6+mc1.20.1.jar', '1.20.1', b'original', b'cambiado'),
            ('realmc-client-0.6.6+mc1.19.jar', '1.19', b'no viene', None),
        ])

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def crear_realclient(self, entradas):
        """entradas: (archivo, versión, contenido del índice, contenido real o None si falta)"""
        shutil.rmtree(self.realclient, ignore_errors=True)
        os.makedirs(os.path.join(self.realclient, 'jars'))
        mods = []
        for archivo, version, indice, real in entradas:
            mods.append({'file': archivo, 'minecraft': [version], 'sha256': hashlib.sha256(indice).hexdigest(), 'java': 21})
            if real is not None:
                with open(os.path.join(self.realclient, 'jars', archivo), 'wb') as f:
                    f.write(real)
        with open(os.path.join(self.realclient, 'mods-manifest-0.6.6.json'), 'w', encoding='utf-8') as f:
            json.dump({'version': 1, 'mods': mods}, f)

    def integrar(self):
        return subprocess.run([sys.executable, SCRIPT, self.motor, '--realclient', self.realclient],
                              capture_output=True, text=True, encoding='utf-8')

    def foto(self):
        archivos = {}
        for base, _, nombres in os.walk(self.motor):
            for n in nombres:
                p = os.path.join(base, n)
                with open(p, 'rb') as f:
                    archivos[os.path.relpath(p, self.motor)] = f.read()
        return archivos

    def test_aplica_todos_los_cambios(self):
        r = self.integrar()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('INTEGRACION_OK', r.stdout)
        for rel, marca in CAMBIOS.items():
            texto = leer(os.path.join(self.motor, rel)).replace('\r\n', '\n')
            self.assertIn(marca, texto, rel)

    def test_segunda_pasada_no_cambia_nada(self):
        self.assertEqual(self.integrar().returncode, 0)
        antes = self.foto()
        r = self.integrar()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertNotIn('editado', r.stdout)
        self.assertEqual(antes, self.foto())

    def test_falla_en_voz_alta_si_falta_un_ancla(self):
        ruta = os.path.join(self.motor, 'Natives', 'LauncherNavigationController.m')
        texto = leer(ruta)
        with open(ruta, 'w', encoding='utf-8', newline='') as f:
            f.write(texto.replace('[PLProfiles updateCurrent];', '[PLProfiles reload];'))
        r = self.integrar()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn('INTEGRACION_INCOMPLETA', r.stdout)
        self.assertNotIn('RPLaunch', leer(ruta), 'un archivo con un ancla rota no se toca a medias')

    def test_cada_fuente_de_realphone_entra_en_el_ejecutable(self):
        self.assertEqual(self.integrar().returncode, 0)
        cmake = leer(os.path.join(self.motor, 'Natives', 'CMakeLists.txt')).replace('\r\n', '\n')
        for nombre in sorted(os.listdir(FUENTES)):
            copia = os.path.join(self.motor, 'Natives', 'realphone', nombre)
            self.assertTrue(os.path.isfile(copia), nombre)
            if nombre.endswith('.m'):
                self.assertIn('  realphone/%s\n' % nombre, cmake)

    def test_solo_empaqueta_jars_verificados(self):
        r = self.integrar()
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        destino = os.path.join(self.motor, 'Natives', 'resources', 'realclient')
        self.assertEqual(os.listdir(os.path.join(destino, 'jars')), ['realmc-client-0.6.6+mc1.21.11.jar'])
        self.assertTrue(os.path.isfile(os.path.join(destino, 'mods-manifest-0.6.6.json')))
        self.assertIn('1 de 3', r.stdout)

    def test_sin_ningun_jar_valido_falla(self):
        self.crear_realclient([('realmc-client-0.6.6+mc1.20.1.jar', '1.20.1', b'original', b'cambiado')])
        r = self.integrar()
        self.assertEqual(r.returncode, 1, r.stdout)
        self.assertIn('INTEGRACION_INCOMPLETA', r.stdout)

    def test_marca_realphone(self):
        self.assertEqual(self.integrar().returncode, 0)
        natives = os.path.join(self.motor, 'Natives')
        plist = leer(os.path.join(natives, 'Info.plist'))
        self.assertIn('<string>RealPhone</string>', plist)
        self.assertNotIn('Angel Aura Amethyst uses', plist)
        for nombre in ('entitlements.sideload.xml', 'entitlements.trollstore.xml'):
            texto = leer(os.path.join(self.motor, nombre))
            self.assertNotIn('org.angelauramc.amethyst', texto, nombre)
            self.assertIn('com.nationcode.realphone', texto, nombre)
        with open(os.path.join(IOS, 'marca', 'AppIcon-1024.png'), 'rb') as f:
            icono = f.read()
        with open(os.path.join(natives, 'Assets.xcassets', 'AppIcon-Light.appiconset', '1024x1024.png'), 'rb') as f:
            self.assertEqual(icono, f.read())
        self.assertTrue(os.path.isfile(os.path.join(natives, 'resources', 'RPCrown@3x.png')))


if __name__ == '__main__':
    unittest.main()
