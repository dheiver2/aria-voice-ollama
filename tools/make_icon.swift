import AppKit

// Gera o ícone da ÁRIA (1024x1024) nativamente com AppKit/CoreGraphics.
// Orb violeta (identidade do OrbView.idle) num squircle estilo macOS + waveform.

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no ctx") }

func hex(_ h: String, _ a: CGFloat = 1) -> NSColor {
    var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
    return NSColor(red: CGFloat((v>>16)&0xff)/255, green: CGFloat((v>>8)&0xff)/255,
                   blue: CGFloat(v&0xff)/255, alpha: a)
}

// --- Fundo squircle (rounded rect estilo macOS, ~18% de raio) ---
let inset: CGFloat = S * 0.09
let rect = CGRect(x: inset, y: inset, width: S - inset*2, height: S - inset*2)
let radius = rect.width * 0.225
let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

// Gradiente de fundo escuro -> violeta profundo
let bgGrad = NSGradient(colors: [hex("2A1B4D"), hex("1A1033")],
                        atLocations: [0, 1], colorSpace: .deviceRGB)!
squircle.addClip()
bgGrad.draw(in: rect, angle: -90)

// --- Blobs violeta desfocados (como o orb idle) ---
let cx = S/2, cy = S/2
let blobs: [(String, CGFloat, CGFloat, CGFloat)] = [
    ("7C3AED", -60,  70, 330),
    ("4F46E5",  90, -40, 300),
    ("A78BFA", -30, -90, 260),
    ("6D28D9",  70, 110, 290),
]
ctx.saveGState()
for (h, dx, dy, size) in blobs {
    let color = hex(h, 0.85).cgColor
    ctx.setShadow(offset: .zero, blur: 90, color: color)
    ctx.setFillColor(color)
    let r = CGRect(x: cx + dx - size/2, y: cy + dy - size/2, width: size, height: size)
    ctx.fillEllipse(in: r)
}
ctx.restoreGState()

// --- Disco central luminoso (clipado num círculo p/ ficar suave) ---
let coreR: CGFloat = 300
let coreRect = CGRect(x: cx - coreR, y: cy - coreR, width: coreR*2, height: coreR*2)
ctx.saveGState()
NSBezierPath(ovalIn: coreRect).addClip()
let coreGrad = NSGradient(colors: [hex("B79BFF", 0.98), hex("7C3AED", 0.95), hex("5B21B6", 0.9)],
                          atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!
coreGrad.draw(in: coreRect, relativeCenterPosition: NSPoint(x: -0.25, y: 0.3))
// Realce especular no topo-esquerdo (dentro do disco)
ctx.setShadow(offset: .zero, blur: 50, color: NSColor.white.withAlphaComponent(0.55).cgColor)
ctx.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
ctx.fillEllipse(in: CGRect(x: cx - 170, y: cy + 70, width: 200, height: 140))
ctx.restoreGState()

// --- Waveform central (branco) ---
let barW: CGFloat = 34
let gap: CGFloat = 30
let heights: [CGFloat] = [150, 300, 470, 300, 150]
let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
var x = cx - totalW/2
NSColor.white.setFill()
for h in heights {
    let bar = NSBezierPath(roundedRect: CGRect(x: x, y: cy - h/2, width: barW, height: h),
                           xRadius: barW/2, yRadius: barW/2)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 24, color: hex("7C3AED", 0.9).cgColor)
    bar.fill()
    ctx.restoreGState()
    x += barW + gap
}

// Aro sutil
squircle.lineWidth = 6
hex("A78BFA", 0.5).setStroke()
squircle.stroke()

img.unlockFocus()

// --- Salvar PNG ---
guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("png fail") }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("✅ \(out)")
