#!/usr/bin/env python3
"""
build_cup_path.py

Traza la silueta de la copa de Europa a partir de una imagen de referencia y
escribe el resultado como código Swift, en dos sitios a la vez:

  · `Champions/CupPath.swift`   — la figura que dibuja la app
  · `scripts/render_icon.swift` — el mismo contorno dentro del icono

Se hace así porque dibujar la copa a mano con curvas de Bézier no salía: la
orejona tiene dos asas en forma de ese que suben por encima del borde, un
collarín bajo la boca y un cuerpo que primero se ensancha y luego se afila, y
todo eso a ojo queda en un trofeo genérico. Trazando la silueta real de una
imagen se consigue la figura exacta, y además queda medida: el script informa
de qué porcentaje del original reproduce el polígono que emite.

    python3 scripts/build_cup_path.py [imagen.jpg]

Necesita `pillow` y `numpy`. La imagen debe tener la copa clara sobre un fondo
oscuro; el script se queda con la mancha conexa más grande, así que los textos
o adornos sueltos alrededor no estorban.
"""

from __future__ import annotations

import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REFERENCIA = Path(sys.argv[1] if len(sys.argv) > 1 else "scripts/orejona-referencia.jpg")
SALIDA_SWIFT = Path("Champions/CupPath.swift")
SALIDA_ICONO = Path("scripts/render_icon.swift")

# Tolerancia del simplificador, en píxeles de la imagen original. Se aplica
# después de suavizar, así que un valor bajo ya no arrastra el escalonado de
# los píxeles: 0,35 deja unos 250 puntos y curvas limpias a 1024 px.
TOLERANCIA = 0.35

# Los agujeros más pequeños que esto no son las asas, sino adornos del logotipo
# (el balón de estrellas): se rellenan.
AREA_MINIMA_HUECO = 400


# -- Segmentación ---------------------------------------------------------

def cargar_mascara(ruta: Path) -> np.ndarray:
    """Copa = píxeles claros y poco saturados sobre un fondo de color."""
    imagen = Image.open(ruta).convert("RGB")
    pix = np.asarray(imagen).astype(int)
    maximo, minimo = pix.max(2), pix.min(2)
    return (maximo > 165) & ((maximo - minimo) < 55)


def componentes(mascara: np.ndarray) -> list[list[tuple[int, int]]]:
    """Componentes conexas por vecindad de cuatro."""
    alto, ancho = mascara.shape
    visto = np.zeros_like(mascara, bool)
    salida = []
    for sy in range(alto):
        for sx in range(ancho):
            if not mascara[sy, sx] or visto[sy, sx]:
                continue
            cola = deque([(sy, sx)])
            visto[sy, sx] = True
            grupo = []
            while cola:
                y, x = cola.popleft()
                grupo.append((y, x))
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    ny, nx = y + dy, x + dx
                    if 0 <= ny < alto and 0 <= nx < ancho \
                       and mascara[ny, nx] and not visto[ny, nx]:
                        visto[ny, nx] = True
                        cola.append((ny, nx))
            salida.append(grupo)
    return salida


def aislar_copa(mascara: np.ndarray) -> tuple[np.ndarray, list]:
    """Deja solo la copa y devuelve los huecos que hay que respetar (las asas)."""
    alto, ancho = mascara.shape
    piezas = sorted(componentes(mascara), key=len, reverse=True)
    copa = np.zeros_like(mascara, bool)
    for y, x in piezas[0]:
        copa[y, x] = True

    # Un hueco es una región de fondo que no llega al borde de la imagen.
    huecos = [g for g in componentes(~copa)
              if not any(y in (0, alto - 1) or x in (0, ancho - 1) for y, x in g)]
    for grupo in huecos:
        if len(grupo) < AREA_MINIMA_HUECO:
            for y, x in grupo:
                copa[y, x] = True
    return copa, [g for g in huecos if len(g) >= AREA_MINIMA_HUECO]


# -- Contorno -------------------------------------------------------------

# Vecinos en sentido horario empezando por el oeste.
VECINOS = [(0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1), (1, 0), (1, -1)]


def contorno(mascara: np.ndarray) -> list[tuple[int, int]]:
    """Trazado de Moore: sigue el borde de la mancha píxel a píxel.

    Se arranca del píxel más alto y, de esos, el más a la izquierda, cuyo
    vecino oeste es fondo por definición: así el primer giro siempre encuentra
    el borde y no hace falta buscar la dirección inicial.
    """
    ys, xs = np.where(mascara)
    inicio = (int(ys[np.argmin(ys * 100000 + xs)]),
              int(xs[np.argmin(ys * 100000 + xs)]))
    actual, anterior = inicio, (inicio[0], inicio[1] - 1)
    salida = [inicio]

    for _ in range(500_000):
        delta = (anterior[0] - actual[0], anterior[1] - actual[1])
        base = VECINOS.index(delta)
        for paso in range(1, 9):
            j = (base + paso) % 8
            ny, nx = actual[0] + VECINOS[j][0], actual[1] + VECINOS[j][1]
            if 0 <= ny < mascara.shape[0] and 0 <= nx < mascara.shape[1] \
               and mascara[ny, nx]:
                anterior = (actual[0] + VECINOS[(j - 1) % 8][0],
                            actual[1] + VECINOS[(j - 1) % 8][1])
                actual = (ny, nx)
                break
        else:
            break
        if actual == inicio:
            break
        salida.append(actual)
    return salida


def suavizar(puntos: list, ventana: int = 9, pasadas: int = 2) -> list:
    """Media móvil sobre el contorno cerrado.

    El trazado sigue el borde píxel a píxel, así que hereda el escalonado de la
    imagen: en el icono a 1024 px se ve como una escalera en las asas.
    Promediar cada punto con sus vecinos lo quita sin mover la figura, porque
    el contorno es denso —cientos de puntos— y la ventana abarca menos de un
    grado de curva.
    """
    salida = list(puntos)
    radio = ventana // 2
    for _ in range(pasadas):
        n = len(salida)
        salida = [
            (sum(salida[(i + k) % n][0] for k in range(-radio, radio + 1)) / ventana,
             sum(salida[(i + k) % n][1] for k in range(-radio, radio + 1)) / ventana)
            for i in range(n)
        ]
    return salida


def simplificar(puntos: list, tolerancia: float) -> list:
    """Ramer–Douglas–Peucker."""
    if len(puntos) < 3:
        return list(puntos)
    P = np.array(puntos, float)
    a, b = P[0], P[-1]
    ab = b - a
    largo = float(np.hypot(*ab))
    v = P - a
    d = np.hypot(*v.T) if largo == 0 else np.abs(ab[0] * v[:, 1] - ab[1] * v[:, 0]) / largo
    i = int(np.argmax(d))
    if d[i] > tolerancia:
        return simplificar(puntos[:i + 1], tolerancia)[:-1] + simplificar(puntos[i:], tolerancia)
    return [puntos[0], puntos[-1]]


# -- Emisión --------------------------------------------------------------

def swift_anillos(anillos: list[list[tuple[float, float]]], sangria: str) -> str:
    bloques = []
    for anillo in anillos:
        puntos = ", ".join(f"({x}, {y})" for x, y in anillo)
        # Se parte en líneas de ~76 columnas para que el fuente sea legible.
        linea, lineas = sangria + "    ", []
        for trozo in puntos.split(", "):
            if len(linea) + len(trozo) > 76:
                lineas.append(linea.rstrip())
                linea = sangria + "    "
            linea += trozo + ", "
        lineas.append(linea.rstrip().rstrip(","))
        bloques.append(sangria + "[\n" + "\n".join(lineas) + "\n" + sangria + "]")
    return ",\n".join(bloques)


PLANTILLA_SWIFT = '''//
//  CupPath.swift
//  Champions
//
//  ⚠️  Generado por `scripts/build_cup_path.py`. No editar a mano:
//      cualquier cambio se pierde la próxima vez que se ejecute el script.
//
//  La silueta de la copa de Europa, trazada de una imagen de referencia y
//  reducida a {puntos} puntos. Reproduce el {precision}% de la figura original.
//
//  Son tres anillos: el contorno de la copa y el hueco de cada asa. Se rellenan
//  con la regla par-impar, que es la que convierte los dos anillos interiores en
//  agujeros de verdad.
//

import SwiftUI

/// Contorno de la copa en un lienzo de 100 × {alto}.
enum CupPath {{

    /// Alto del lienzo de referencia. El ancho es 100.
    static let canvasHeight: CGFloat = {alto}

    /// Anillos del contorno: el primero es la copa, los otros dos las asas.
    static let rings: [[CGPoint]] = [
{anillos}
    ].map {{ $0.map(CGPoint.init) }}
}}

private extension CGPoint {{
    init(_ par: (CGFloat, CGFloat)) {{ self.init(x: par.0, y: par.1) }}
}}

// MARK: - Shape

/// La copa como figura de SwiftUI, escalada al espacio que se le dé.
struct EuropeanCupShape: Shape {{

    func path(in rect: CGRect) -> Path {{
        let k = min(rect.width / 100, rect.height / CupPath.canvasHeight)
        let dx = rect.midX - 50 * k
        let dy = rect.midY - CupPath.canvasHeight / 2 * k

        var path = Path()
        for anillo in CupPath.rings {{
            guard let primero = anillo.first else {{ continue }}
            path.move(to: CGPoint(x: dx + primero.x * k, y: dy + primero.y * k))
            for punto in anillo.dropFirst() {{
                path.addLine(to: CGPoint(x: dx + punto.x * k, y: dy + punto.y * k))
            }}
            path.closeSubpath()
        }}
        return path
    }}
}}

/// La copa lista para usar, con su degradado plateado.
struct EuropeanCupView: View {{

    var size: CGFloat = 72

    private var silver: LinearGradient {{
        LinearGradient(
            colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD3DCEA),
                     Color(hex: 0x8C98AF), Color(hex: 0xE8EEF8)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }}

    var body: some View {{
        EuropeanCupShape()
            // Par-impar: sin esto los huecos de las asas se rellenan y la copa
            // pierde justo lo que la hace reconocible.
            .fill(silver, style: FillStyle(eoFill: true))
            .frame(width: size * 100 / CupPath.canvasHeight, height: size)
            .accessibilityHidden(true)
    }}
}}

#Preview {{
    EuropeanCupView(size: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0B1230))
}}
'''

MARCA_INICIO = "// === CONTORNO GENERADO — inicio ==="
MARCA_FIN = "// === CONTORNO GENERADO — fin ==="


def main() -> int:
    if not REFERENCIA.exists():
        sys.exit(f"ERROR: no encuentro la imagen de referencia {REFERENCIA}")

    print(f"Trazando {REFERENCIA}…")
    copa, huecos = aislar_copa(cargar_mascara(REFERENCIA))

    crudos = [contorno(copa)]
    for grupo in huecos:
        hueco = np.zeros_like(copa)
        for y, x in grupo:
            hueco[y, x] = True
        crudos.append(contorno(hueco))

    anillos = [simplificar(suavizar(r), TOLERANCIA) for r in crudos]
    total = sum(len(r) for r in anillos)
    print(f"  {len(anillos)} anillos · {sum(len(r) for r in crudos)} → {total} puntos")

    ys, xs = np.where(copa)
    y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
    alto, ancho = y1 - y0 + 1, x1 - x0 + 1
    alto_lienzo = 100 * alto / ancho

    # Comprobar cuánto se parece el polígono a la mancha original.
    prueba = Image.new("L", (ancho, alto), 0)
    lapiz = ImageDraw.Draw(prueba)
    lapiz.polygon([(float(x) - x0, float(y) - y0) for y, x in anillos[0]], fill=255)
    for anillo in anillos[1:]:
        lapiz.polygon([(float(x) - x0, float(y) - y0) for y, x in anillo], fill=0)
    precision = 100 * ((np.asarray(prueba) > 127) == copa[y0:y1 + 1, x0:x1 + 1]).mean()
    print(f"  reproduce el {precision:.2f} % del original")

    normal = [[(round((x - x0) * 100 / ancho, 2),
                round((y - y0) * alto_lienzo / alto, 2)) for y, x in anillo]
              for anillo in anillos]

    SALIDA_SWIFT.write_text(
        PLANTILLA_SWIFT.format(
            puntos=total,
            precision=f"{precision:.1f}",
            alto=round(alto_lienzo, 2),
            anillos=swift_anillos(normal, "        "),
        ),
        encoding="utf-8",
    )
    print(f"✅ {SALIDA_SWIFT}")

    # El icono es un script suelto y no puede importar el target: se le
    # inyecta el mismo contorno entre marcas.
    if SALIDA_ICONO.exists():
        fuente = SALIDA_ICONO.read_text(encoding="utf-8")
        if MARCA_INICIO in fuente and MARCA_FIN in fuente:
            bloque = (
                f"{MARCA_INICIO}\n"
                f"// Lo escribe `scripts/build_cup_path.py`. No tocar a mano.\n"
                f"let alturaLienzo: CGFloat = {round(alto_lienzo, 2)}\n"
                f"let anillos: [[(CGFloat, CGFloat)]] = [\n"
                f"{swift_anillos(normal, '    ')}\n"
                f"]\n"
                f"{MARCA_FIN}"
            )
            ini = fuente.index(MARCA_INICIO)
            fin = fuente.index(MARCA_FIN) + len(MARCA_FIN)
            SALIDA_ICONO.write_text(fuente[:ini] + bloque + fuente[fin:], encoding="utf-8")
            print(f"✅ {SALIDA_ICONO} (contorno actualizado)")
        else:
            print(f"⚠️  {SALIDA_ICONO} no tiene las marcas; no se ha tocado")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
