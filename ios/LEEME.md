# RealPhone para iPhone

RealPhone para iPhone abre Minecraft Java con el mod RealClient, igual que la versión Android. Por debajo usa
el motor [Amethyst-iOS](https://github.com/AngelAuraMC/Amethyst-iOS) (Java ARM64, LWJGL y los renderizadores),
fijado al commit `f98c4133c72d39e06ceac42b57cc4477c52105fc`. Encima van la marca de RealPhone, el acceso por
invitación de NationCode, la instalación de Fabric y RealClient y el ticket de módulos de RealMC.

Apple no admite en el App Store un launcher que descarga y ejecuta código con JIT, así que la app se instala
por fuera: TrollStore, SideStore o AltStore.

## Qué hay en esta carpeta

| Ruta | Qué es |
|---|---|
| `realphone/` | Código Objective-C de RealPhone. Se copia a `Natives/realphone/` del motor |
| `integracion/integrar_ios.py` | Aplica RealPhone sobre un checkout de Amethyst-iOS. Se puede repetir sin romper nada |
| `integracion/test_integrar_ios.py` | Pruebas del script contra el motor fijado |
| `tests/RPCoreTests.m` | Pruebas de la lógica (catálogo, jars, Fabric, ticket, acceso). Corren en macOS |
| `marca/` | Iconos y corona. `generar_iconos.ps1` los vuelve a generar desde la corona de Android |
| `../.github/workflows/realphone-ios.yml` | Compila el `.ipa` en GitHub Actions |

## Compilar

Hace falta macOS (Xcode, el SDK de iOS y `ldid`). Desde Windows se compila con GitHub Actions:

1. Sube esta carpeta `RealPhone` a un repositorio de GitHub. El `.gitignore` de la raíz solo deja entrar lo que
   necesita la compilación (59 archivos, unos 103 MB con los jars de RealClient): `ios/`, el workflow y
   `engine-src/integracion/realphone/src/main/assets/realclient/`. Las llaves (`*.jks`, `*.keystore`,
   `realphone.properties`, `backend/ADMIN_TOKEN.txt`, `backend/private.jwk.json`) quedan fuera.
2. En GitHub abre **Actions > RealPhone iOS > Run workflow**. Tarda bastante: compila el motor entero y descarga
   los Java para iOS.
3. Cuando termine, en la ejecución aparecen tres descargas:
   - `RealPhone.ipa` para SideStore o AltStore.
   - `RealPhone-trollstore.tipa` para TrollStore.
   - `SHA256SUMS` con el hash de los dos.

El primer paso del workflow corre las pruebas. Si fallan, no se genera el `.ipa`.

Para probar el script de integración en Windows hace falta Python 3 y el motor clonado en `ios/motor/`:

```
git clone https://github.com/AngelAuraMC/Amethyst-iOS.git ios/motor/Amethyst-iOS
git -C ios/motor/Amethyst-iOS checkout f98c4133c72d39e06ceac42b57cc4477c52105fc
python -m unittest discover -s ios/integracion -v
```

## Instalar en el iPhone

Requisitos: iOS 14 o más nuevo. Amethyst recomienda un iPhone XS o más nuevo (no XR ni SE de 2.ª generación); en
modelos más viejos funciona, pero va lento.

| Método | Qué archivo | Ventajas | Limitaciones |
|---|---|---|---|
| TrollStore | `RealPhone-trollstore.tipa` | Firma permanente, JIT automático, más memoria | Solo en las versiones de iOS que TrollStore admite |
| SideStore | `RealPhone.ipa` | Se renueva desde el propio iPhone | El JIT se activa con SideStore o StikDebug; la primera vez hace falta un ordenador |
| AltStore | `RealPhone.ipa` | Sencillo | Necesita AltServer en un ordenador de la misma red para el JIT |

Con un Apple ID gratuito, SideStore y AltStore firman la app por 7 días y hay que renovarla. Los servicios de
firma que no usan tu UDID (certificados de distribución) no sirven: les falta el permiso para depurar, que es
lo que permite el JIT.

### JIT

Java necesita JIT para ir a una velocidad jugable, y iOS solo lo permite a una app que se está depurando. Al
pulsar Jugar, RealPhone pide el JIT a TrollStore, StikDebug o SideStore según lo que haya instalado, y espera
hasta que esté activo. En iOS 17 y 18 hace falta un ordenador la primera vez para emparejar SideStore o
StikDebug. La guía de Amethyst explica cada método: <https://wiki.angelauramc.dev/wiki/faq/ios/JIT.html>.

## Primer uso

1. Abre RealPhone. Escribe tu correo y el código de invitación que te dio NationCode y pulsa
   **Activar este iPhone**. Cada código sirve una sola vez y para un solo dispositivo
   (`INVITAR_USUARIO.bat` en el PC los crea).
2. Añade tu cuenta de Minecraft con el botón de cuenta del menú: Microsoft (premium) o local (sin premium).
3. En la barra de abajo elige un perfil **RealClient &lt;versión&gt;** y pulsa **Jugar**.

Al pulsar Jugar, RealPhone hace esto antes de que el motor descargue el juego:

1. Comprueba tu acceso con el servidor (`/v1/me`). Sin conexión vale hasta la fecha `offlineUntil` que da el
   servidor (7 días por defecto). Si NationCode revocó la cuenta o el iPhone, vuelve a la pantalla de acceso.
2. Instala el perfil de Fabric (o Legacy Fabric en 1.8.9) desde `meta.fabricmc.net` / `meta.legacyfabric.net`.
3. Copia a `mods/` el jar de RealClient de esa versión si su SHA-256 coincide con el catálogo firmado. Los
   RealClient de otras versiones se renombran a `.disabled`.
4. Instala Fabric API desde Modrinth y comprueba su SHA-1. En 1.8.9 la desactiva, porque ahí hace fallar el juego.
5. Pide el ticket de módulos a RealMC (como el launcher de PC). Si no lo consigue, el juego abre igual con los
   módulos apagados y RealPhone lo avisa.

Cada versión tiene su propia carpeta de juego: `Documents/instances/default/realphone/<loader>-<versión>/` (por
ejemplo `fabric-1.21.11` o `legacy-fabric-1.8.9`). Allí están `mods/` y `config/`, y se ven desde la app Archivos.

Dentro de la partida, el botón **R** abre el menú de módulos de RealClient (envía Shift derecho) y, con un menú
abierto, lo cierra (envía Esc). Se puede arrastrar a otro sitio y recuerda dónde lo dejaste.

Para cerrar la sesión: menú lateral > **Cerrar sesión de RealPhone**. Para volver a entrar hace falta un código
nuevo.

## Estado real

| Área | Estado |
|---|---|
| Acceso por invitación, revocación y uso sin conexión | Hecho. Token en el llavero del iPhone. Probado con un servidor falso en `RPCoreTests.m` |
| RealClient verificado por SHA-256 | Hecho. Entran 21 de las 30 versiones Fabric: para 1.20.2, 1.20.3, 1.20.6 y 1.21.2 a 1.21.7 no hay jar en la carpeta de Android |
| Fabric, Legacy Fabric y Fabric API | Hecho, igual que en Android |
| Ticket de módulos de RealMC | Hecho, mismo flujo que `RealClientTicket.kt`. El ticket no se escribe en el registro |
| Botón R de módulos | Hecho |
| NeoForge | No disponible, igual que en Android |
| Editor de controles de RealPhone | No portado: se usan los controles táctiles de Amethyst (menú lateral, controles personalizados) |
| Compilación | **Sin compilar todavía**: se escribió en Windows. La primera compilación es la del workflow |
| Prueba en un iPhone real | **Pendiente** |

Si el ticket de módulos o el jar fallan, el juego abre igual y un aviso dice por qué. Si falla el acceso,
Fabric o Fabric API, no se juega y el aviso dice qué hacer.

## Licencia (GPL-3.0): léelo antes de repartir el .ipa

Amethyst-iOS tiene licencia GPL-3.0, y RealPhone para iPhone es un programa derivado que se enlaza con él en un
solo ejecutable. Al repartir `RealPhone.ipa` o `RealPhone-trollstore.tipa`:

- El código de RealPhone para iPhone (`ios/realphone`, `ios/integracion`, el workflow) queda bajo GPL-3.0.
- Quien reciba la app tiene derecho al código fuente completo: Amethyst-iOS en el commit fijado más esta carpeta
  `ios/`. Lo más simple es publicarlo en un repositorio y poner el enlace donde se descarga la app.
- Hay que incluir el texto de la GPL-3.0 (el `LICENSE` de Amethyst-iOS) y los avisos de terceros de su README
  (OpenJDK de Azul Zulu con GPLv2 + Classpath Exception, LWJGL, GL4ES, MoltenVK, Mesa y los demás).
- No se pueden añadir condiciones que la GPL no permite, como prohibir que otros la modifiquen o la compartan.

Por lo mismo, la pantalla de invitación no impide que alguien con el código compile una versión sin ella. Lo que
protege de verdad está en los servidores: el token de `/v1/*` que revoca NationCode y el ticket que firma RealMC.
Esta diferencia no existe en Android, donde Amethyst-Android tiene licencia LGPL-3.0.

## Actualizar el motor

1. Cambia `AMETHYST_COMMIT` en `.github/workflows/realphone-ios.yml` y el commit de `ios/motor/Amethyst-iOS`.
2. Corre `python -m unittest discover -s ios/integracion -v`. Si un texto original del motor cambió, el script
   dice cuál y termina con `INTEGRACION_INCOMPLETA`. Hay que ajustar ese parche en `integrar_ios.py`.
3. Lanza el workflow y prueba en un iPhone antes de repartir.
