//
//  CupPath.swift
//  Champions
//
//  ⚠️  Generado por `scripts/build_cup_path.py`. No editar a mano:
//      cualquier cambio se pierde la próxima vez que se ejecute el script.
//
//  La silueta de la copa de Europa, trazada de una imagen de referencia y
//  reducida a 191 puntos. Reproduce el 98.3% de la figura original.
//
//  Son tres anillos: el contorno de la copa y el hueco de cada asa. Se rellenan
//  con la regla par-impar, que es la que convierte los dos anillos interiores en
//  agujeros de verdad.
//

import SwiftUI

/// Contorno de la copa en un lienzo de 100 × 158.95.
enum CupPath {

    /// Alto del lienzo de referencia. El ancho es 100.
    static let canvasHeight: CGFloat = 158.95

    /// Anillos del contorno: el primero es la copa, los otros dos las asas.
    static let rings: [[CGPoint]] = [
        [
            (18.42, 0.32), (20.53, 0.31), (23.16, 0.74), (25.26, 1.57),
            (27.32, 2.94), (29.15, 4.78), (30.49, 6.84), (31.49, 9.47),
            (31.9, 12.11), (31.77, 14.74), (31.24, 17.37), (30.29, 20.0),
            (28.8, 22.63), (26.24, 25.61), (20.59, 29.84), (18.7, 32.14),
            (18.39, 33.14), (18.51, 34.46), (18.97, 35.11), (19.7, 35.47),
            (21.08, 35.51), (25.79, 34.48), (30.53, 33.92), (42.11, 33.16),
            (55.26, 33.16), (66.32, 33.75), (72.63, 34.48), (77.89, 35.63),
            (79.77, 35.41), (80.46, 34.87), (80.87, 34.09), (80.94, 33.15),
            (80.43, 31.65), (78.86, 29.85), (73.79, 26.28), (71.21, 23.62),
            (69.89, 21.58), (68.67, 18.95), (67.49, 14.21), (67.47, 11.58),
            (67.8, 9.47), (69.34, 5.85), (70.84, 3.99), (72.7, 2.43), (76.32,
            0.79), (80.0, 0.42), (83.16, 0.71), (85.79, 1.55), (88.41, 3.09),
            (90.39, 4.82), (92.44, 7.37), (94.55, 11.05), (96.11, 14.74),
            (97.34, 18.95), (98.67, 25.79), (99.4, 36.32), (98.71, 45.26),
            (97.32, 54.74), (93.96, 68.95), (89.51, 82.11), (83.72, 95.79),
            (72.44, 117.89), (64.55, 131.05), (61.33, 137.37), (60.29,
            140.53), (60.21, 142.11), (60.51, 143.68), (61.92, 146.16),
            (65.26, 148.92), (71.01, 151.77), (73.31, 153.42), (75.98,
            156.66), (75.93, 157.41), (74.65, 157.83), (64.21, 157.91),
            (56.84, 158.41), (31.58, 158.42), (24.26, 158.33), (23.02,
            158.09), (22.43, 157.52), (23.25, 155.87), (26.52, 152.68),
            (28.44, 151.38), (34.73, 148.14), (37.07, 146.17), (38.06,
            144.72), (38.63, 143.16), (38.59, 140.0), (37.63, 137.37), (34.5,
            131.05), (26.0, 116.84), (21.81, 107.89), (16.63, 97.89), (12.78,
            89.47), (7.97, 77.37), (4.81, 67.37), (2.94, 60.0), (0.78,
            47.37), (0.02, 38.95), (0.06, 30.53), (0.79, 24.21), (2.35,
            17.37), (4.42, 11.58), (7.15, 6.88), (10.14, 3.71), (13.68,
            1.49), (17.89, 0.37)
        ],
        [
            (18.95, 4.11), (21.05, 4.13), (22.63, 4.58), (25.45, 6.54),
            (27.21, 9.47), (27.71, 11.58), (27.78, 13.68), (27.14, 17.36),
            (26.0, 19.82), (24.52, 21.44), (19.48, 24.72), (17.55, 26.43),
            (15.78, 28.95), (14.95, 31.58), (14.92, 34.21), (15.69, 37.37),
            (16.88, 40.0), (19.62, 44.21), (20.23, 46.32), (19.84, 47.89),
            (18.78, 49.47), (13.7, 54.49), (13.0, 55.87), (12.7, 57.37),
            (12.77, 66.32), (13.5, 71.58), (13.89, 77.37), (15.35, 87.39),
            (14.63, 86.19), (13.31, 82.63), (10.11, 72.63), (6.52, 58.42),
            (4.39, 45.26), (3.75, 38.42), (3.7, 32.11), (4.28, 26.32), (5.28,
            21.05), (6.69, 16.32), (8.6, 12.11), (10.57, 9.09), (12.74,
            6.93), (15.79, 5.06), (18.42, 4.2)
        ],
        [
            (77.89, 4.17), (79.47, 3.98), (81.05, 4.18), (84.74, 5.61),
            (87.81, 7.98), (90.25, 11.05), (92.4, 15.26), (94.05, 20.53),
            (94.88, 24.74), (95.69, 32.11), (95.72, 36.32), (95.03, 45.26),
            (94.29, 51.05), (92.9, 58.42), (90.48, 68.42), (87.7, 77.89),
            (84.94, 85.79), (83.3, 89.2), (86.13, 69.47), (86.78, 56.85),
            (86.48, 55.35), (85.77, 54.0), (80.36, 49.22), (79.42, 47.8),
            (79.11, 46.3), (79.51, 44.74), (82.43, 40.0), (83.58, 37.37),
            (84.41, 34.21), (84.39, 31.58), (83.17, 28.44), (81.29, 26.06),
            (79.41, 24.52), (75.35, 21.91), (73.29, 19.86), (72.1, 17.37),
            (71.65, 14.74), (71.72, 11.05), (72.52, 8.46), (74.35, 6.13),
            (77.37, 4.32)
        ]
    ].map { $0.map(CGPoint.init) }
}

private extension CGPoint {
    init(_ par: (CGFloat, CGFloat)) { self.init(x: par.0, y: par.1) }
}

// MARK: - Shape

/// La copa como figura de SwiftUI, escalada al espacio que se le dé.
struct EuropeanCupShape: Shape {

    func path(in rect: CGRect) -> Path {
        let k = min(rect.width / 100, rect.height / CupPath.canvasHeight)
        let dx = rect.midX - 50 * k
        let dy = rect.midY - CupPath.canvasHeight / 2 * k

        var path = Path()
        for anillo in CupPath.rings {
            guard let primero = anillo.first else { continue }
            path.move(to: CGPoint(x: dx + primero.x * k, y: dy + primero.y * k))
            for punto in anillo.dropFirst() {
                path.addLine(to: CGPoint(x: dx + punto.x * k, y: dy + punto.y * k))
            }
            path.closeSubpath()
        }
        return path
    }
}

/// La copa lista para usar, con su degradado plateado.
struct EuropeanCupView: View {

    var size: CGFloat = 72

    private var silver: LinearGradient {
        LinearGradient(
            colors: [Color(hex: 0xFFFFFF), Color(hex: 0xD3DCEA),
                     Color(hex: 0x8C98AF), Color(hex: 0xE8EEF8)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    var body: some View {
        EuropeanCupShape()
            // Par-impar: sin esto los huecos de las asas se rellenan y la copa
            // pierde justo lo que la hace reconocible.
            .fill(silver, style: FillStyle(eoFill: true))
            .frame(width: size * 100 / CupPath.canvasHeight, height: size)
            .accessibilityHidden(true)
    }
}

#Preview {
    EuropeanCupView(size: 220)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(hex: 0x0B1230))
}
