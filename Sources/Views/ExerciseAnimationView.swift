import SwiftUI
import Foundation

// MARK: - Datenmodell der Bewegungsanimationen

struct AnimPose {
    var hip: CGPoint
    var torso: Double
    var head: Double = 0
    var hand: CGPoint? = nil
    var hand2: CGPoint? = nil
    var handT: CGPoint? = nil
    var handRel: CGPoint? = nil
    var foot: CGPoint = CGPoint(x: 0.5, y: 0.06)
    var foot2: CGPoint? = nil
    var kneeS: Double = 1
    var knee2S: Double? = nil
    var elbowS: Double = -1
    var elbow2S: Double? = nil
    var footA: Double = 0
    var foot2A: Double? = nil
}

enum AnimAnchor {
    case point(CGPoint)
    case joint(String, CGPoint)
}

enum AnimProp {
    case rect(x: Double, y: Double, w: Double, h: Double, light: Bool)
    case plate(at: AnimAnchor, rad: Double, front: Bool)
    case dumbbell(at: AnimAnchor, angle: Double, front: Bool)
    case cable(from: AnimAnchor, to: AnimAnchor)
    case bar(from: AnimAnchor, to: AnimAnchor)
    case line(from: CGPoint, to: CGPoint, width: Double)

    var isFront: Bool {
        switch self {
        case .plate(_, _, let f), .dumbbell(_, _, let f): return f
        default: return false
        }
    }
}

struct ExerciseAnimation {
    var key: String
    var label: String
    var front: Bool
    var highlight: Set<String>
    var gluteDir: Double
    var zoom: Double
    var thighScale: Double
    var floor: Bool
    var props: [AnimProp]
    var a: AnimPose
    var b: AnimPose

    static func named(_ key: String) -> ExerciseAnimation? { key.isEmpty ? nil : library[key] }

    /// Auswahlliste für eigene Übungen
    static var choices: [ExerciseAnimation] {
        library.values.sorted { $0.label < $1.label }
    }
}

// MARK: - Kinematik

private enum Rig {
    static let torso = 0.25, upper = 0.14, fore = 0.13, thigh = 0.20, shin = 0.19, foot = 0.055
    static let head = 0.085, headR = 0.045, hipW = 0.045, shW = 0.075
    static let canvasH = 0.75

    static func dir(_ deg: Double) -> CGPoint {
        let r: Double = deg * Double.pi / 180
        return CGPoint(x: Foundation.cos(r), y: Foundation.sin(r))
    }
    static func add(_ p: CGPoint, _ v: CGPoint, _ s: Double = 1) -> CGPoint {
        CGPoint(x: p.x + v.x * s, y: p.y + v.y * s)
    }
    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    /// Zwei-Gelenk-IK: liefert (Mittelgelenk, Endpunkt)
    static func ik(_ a: CGPoint, _ b: CGPoint, _ l1: Double, _ l2: Double, _ side: Double) -> (CGPoint, CGPoint) {
        let ax = Double(a.x), ay = Double(a.y)
        let dx = Double(b.x) - ax, dy = Double(b.y) - ay
        var dist: Double = (dx * dx + dy * dy).squareRoot()
        dist = Swift.max(Swift.abs(l1 - l2) + 1e-4, Swift.min(l1 + l2 - 1e-4, dist))
        let base: Double = Foundation.atan2(dy, dx)
        let c: Double = (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)
        let ang: Double = Foundation.acos(Swift.max(-1, Swift.min(1, c)))
        let jx: Double = ax + l1 * Foundation.cos(base + side * ang)
        let jy: Double = ay + l1 * Foundation.sin(base + side * ang)
        let ex: Double = ax + dist * Foundation.cos(base)
        let ey: Double = ay + dist * Foundation.sin(base)
        return (CGPoint(x: jx, y: jy), CGPoint(x: ex, y: ey))
    }

    struct Resolved {
        var hip: CGPoint, torso: Double, head: Double
        var hand: CGPoint?, hand2: CGPoint?, handT: CGPoint?, handRel: CGPoint?
        var foot: CGPoint, foot2: CGPoint
        var kneeS: Double, knee2S: Double, elbowS: Double, elbow2S: Double, footA: Double, foot2A: Double
    }

    static func resolve(_ p: AnimPose) -> Resolved {
        Resolved(hip: p.hip, torso: p.torso, head: p.head, hand: p.hand, hand2: p.hand2 ?? p.hand, handT: p.handT, handRel: p.handRel,
                 foot: p.foot, foot2: p.foot2 ?? p.foot, kneeS: p.kneeS, knee2S: p.knee2S ?? p.kneeS,
                 elbowS: p.elbowS, elbow2S: p.elbow2S ?? p.elbowS, footA: p.footA, foot2A: p.foot2A ?? p.footA)
    }

    static func blend(_ pa: AnimPose, _ pb: AnimPose, _ t: Double) -> Resolved {
        let a = resolve(pa), b = resolve(pb)
        func opt(_ x: CGPoint?, _ y: CGPoint?) -> CGPoint? {
            if let x, let y { return lerp(x, y, t) }
            return t < 0.5 ? x : y
        }
        return Resolved(hip: lerp(a.hip, b.hip, t), torso: lerp(a.torso, b.torso, t), head: lerp(a.head, b.head, t),
                        hand: opt(a.hand, b.hand), hand2: opt(a.hand2, b.hand2), handT: opt(a.handT, b.handT),
                        handRel: opt(a.handRel, b.handRel), foot: lerp(a.foot, b.foot, t), foot2: lerp(a.foot2, b.foot2, t),
                        kneeS: t < 0.5 ? a.kneeS : b.kneeS, knee2S: t < 0.5 ? a.knee2S : b.knee2S,
                        elbowS: t < 0.5 ? a.elbowS : b.elbowS, elbow2S: t < 0.5 ? a.elbow2S : b.elbow2S,
                        footA: lerp(a.footA, b.footA, t), foot2A: lerp(a.foot2A, b.foot2A, t))
    }

    static func joints(_ p: Resolved, front: Bool, thighScale: Double) -> [String: CGPoint] {
        var j: [String: CGPoint] = [:]
        let sh = add(p.hip, dir(p.torso), torso)
        j["hip"] = p.hip
        j["shoulder"] = sh
        j["head"] = add(sh, dir(p.torso + p.head), head)
        let hipN = front ? CGPoint(x: p.hip.x + hipW, y: p.hip.y) : p.hip
        let hipF = front ? CGPoint(x: p.hip.x - hipW, y: p.hip.y) : p.hip
        let shN = front ? CGPoint(x: sh.x + shW, y: sh.y) : sh
        let shF = front ? CGPoint(x: sh.x - shW, y: sh.y) : sh
        j["hipN"] = hipN; j["hipF"] = hipF; j["shN"] = shN; j["shF"] = shF
        var hand = p.hand ?? add(sh, CGPoint(x: 0.02, y: -0.25))
        var hand2 = p.hand2 ?? hand
        if let t = p.handT {
            hand = add(add(sh, dir(p.torso), t.x), dir(p.torso + 90), t.y)
            hand2 = hand
        }
        if let r = p.handRel {
            hand = add(sh, r)
            hand2 = hand
        }
        let th = thigh * thighScale
        let leg = ik(hipN, p.foot, th, shin, p.kneeS)
        let leg2 = ik(hipF, p.foot2, th, shin, p.knee2S)
        let arm = ik(shN, hand, upper, fore, p.elbowS)
        let arm2 = ik(shF, hand2, upper, fore, p.elbow2S)
        j["knee"] = leg.0; j["ankle"] = leg.1
        j["knee2"] = leg2.0; j["ankle2"] = leg2.1
        j["elbow"] = arm.0; j["wrist"] = arm.1
        j["elbow2"] = arm2.0; j["wrist2"] = arm2.1
        j["toe"] = add(leg.1, dir(p.footA), foot)
        j["toe2"] = add(leg2.1, dir(p.foot2A), foot)
        return j
    }
}

// MARK: - Darstellung

struct ExerciseAnimationView: View {
    var animation: ExerciseAnimation
    var animated: Bool = true
    /// Dauer eines kompletten Bewegungszyklus
    var period: Double = 2.8
    /// Phase, wenn nicht animiert (0 = Start, 1 = Endposition)
    var staticPhase: Double = 1
    @State private var paused = false

    var body: some View {
        Group {
            if animated && !paused {
                TimelineView(.animation) { ctx in
                    canvas(t: phase(ctx.date))
                }
            } else {
                canvas(t: animated ? 0.5 : staticPhase)
            }
        }
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture { if animated { paused.toggle() } }
        .accessibilityLabel("Animation: \(animation.label)")
    }

    /// Hin und zurück mit kurzem Halten an Start- und Endposition
    private func phase(_ date: Date) -> Double {
        let x = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        func ease(_ v: Double) -> Double { v * v * (3 - 2 * v) }
        switch x {
        case ..<0.1: return 0
        case ..<0.5: return ease((x - 0.1) / 0.4)
        case ..<0.6: return 1
        default: return ease(1 - (x - 0.6) / 0.4)
        }
    }

    private func canvas(t: Double) -> some View {
        Canvas { ctx, size in
            draw(ctx: &ctx, size: size, t: t)
        }
    }

    private func draw(ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let anim = animation
        let z = anim.zoom
        let w = size.width
        let hPx = size.height
        func P(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (0.5 + (p.x - 0.5) * z) * w, y: hPx - p.y * z * w)
        }
        let pose = Rig.blend(anim.a, anim.b, t)
        let j = Rig.joints(pose, front: anim.front, thighScale: anim.thighScale)

        let ink = Theme.ink
        let far = Theme.muted.opacity(0.45)
        let rose = Theme.rose
        let prop = Color.dynamic("A88F78", "8F7C6A")
        let light = Theme.line

        func seg(_ a: CGPoint?, _ b: CGPoint?, _ color: Color, _ width: Double) {
            guard let a, let b else { return }
            var path = Path()
            path.move(to: P(a)); path.addLine(to: P(b))
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width * w * z, lineCap: .round, lineJoin: .round))
        }
        func dot(_ p: CGPoint?, _ r: Double, _ color: Color) {
            guard let p else { return }
            let c = P(p), rr = r * w * z
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(color))
        }
        func color(_ part: String, _ base: Color) -> Color { anim.highlight.contains(part) ? rose : base }
        func anchor(_ a: AnimAnchor) -> CGPoint? {
            switch a {
            case .point(let p): return p
            case .joint(let name, let off):
                guard let base = j[name] else { return nil }
                return CGPoint(x: base.x + off.x, y: base.y + off.y)
            }
        }
        func drawProp(_ p: AnimProp) {
            switch p {
            case .rect(let x, let y, let rw, let rh, let isLight):
                let a = P(CGPoint(x: x, y: y + rh)), b = P(CGPoint(x: x + rw, y: y))
                let r = CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
                ctx.fill(Path(roundedRect: r, cornerRadius: 0.012 * w), with: .color(isLight ? light : prop.opacity(0.85)))
            case .plate(let at, let rad, _):
                guard let c0 = anchor(at) else { return }
                let c = P(c0), rr = rad * w * z
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(prop), lineWidth: 0.018 * w * z)
                dot(c0, 0.012, prop)
            case .dumbbell(let at, let angle, _):
                guard let c = anchor(at) else { return }
                let v = Rig.dir(angle), h = 0.03
                let p1 = CGPoint(x: c.x - v.x * h, y: c.y - v.y * h), p2 = CGPoint(x: c.x + v.x * h, y: c.y + v.y * h)
                seg(p1, p2, prop, 0.012)
                dot(p1, 0.018, prop); dot(p2, 0.018, prop)
            case .cable(let from, let to):
                guard let a = anchor(from), let b = anchor(to) else { return }
                var path = Path(); path.move(to: P(a)); path.addLine(to: P(b))
                ctx.stroke(path, with: .color(prop), lineWidth: max(1, 0.006 * w))
                dot(a, 0.014, prop)
            case .bar(let from, let to):
                seg(anchor(from), anchor(to), prop, 0.014)
            case .line(let from, let to, let width):
                seg(from, to, prop.opacity(0.85), width)
            }
        }

        if anim.floor {
            var path = Path()
            path.move(to: P(CGPoint(x: 0.03, y: 0.06))); path.addLine(to: P(CGPoint(x: 0.97, y: 0.06)))
            ctx.stroke(path, with: .color(light), lineWidth: max(1, 0.006 * w))
        }
        for p in anim.props where !p.isFront { drawProp(p) }

        // Abgewandte Seite (heller)
        seg(j["hipF"], j["knee2"], anim.front ? color("thigh", far) : far, 0.034)
        seg(j["knee2"], j["ankle2"], far, 0.03)
        seg(j["ankle2"], j["toe2"], far, 0.024)
        seg(j["shF"], j["elbow2"], anim.front ? color("upper", far) : far, 0.03)
        seg(j["elbow2"], j["wrist2"], far, 0.026)

        // Rumpf
        if anim.front, let a = j["shF"], let b = j["shN"], let c = j["hipN"], let d = j["hipF"] {
            var path = Path()
            path.move(to: P(a)); path.addLine(to: P(b)); path.addLine(to: P(c)); path.addLine(to: P(d)); path.closeSubpath()
            ctx.fill(path, with: .color(color("torso", ink)))
        } else {
            seg(j["hip"], j["shoulder"], color("torso", ink), 0.06)
        }
        if anim.highlight.contains("glute"), !anim.front, let hip = j["hip"] {
            dot(Rig.add(hip, Rig.dir(anim.gluteDir), 0.02), 0.04, rose)
        }
        // Zugewandte Seite
        seg(j["hipN"], j["knee"], color("thigh", ink), 0.04)
        seg(j["knee"], j["ankle"], color("shin", ink), 0.034)
        seg(j["ankle"], j["toe"], ink, 0.026)
        seg(j["shN"], j["elbow"], color("upper", ink), 0.034)
        seg(j["elbow"], j["wrist"], color("fore", ink), 0.028)
        dot(j["head"], Rig.headR, ink)

        for p in anim.props where p.isFront { drawProp(p) }
    }
}

// MARK: - Bausteine für die App

extension Exercise {
    var animation: ExerciseAnimation? {
        ExerciseAnimation.named(animationKey) ?? ExerciseAnimation.defaultKeys[name].flatMap { ExerciseAnimation.named($0) }
    }
}

/// Kleine Vorschau (z. B. in Listen)
struct ExerciseThumb: View {
    var animation: ExerciseAnimation?
    var animated: Bool = false
    var width: CGFloat = 56

    var body: some View {
        Group {
            if let animation {
                ExerciseAnimationView(animation: animation, animated: animated)
            } else {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title3).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: width, height: width * 0.75)
        .background(Theme.beige.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// Große Ansicht: Animation + Technik
struct ExerciseDemoSheet: View {
    @Environment(\.dismiss) private var dismiss
    var name: String
    var animation: ExerciseAnimation?
    var muscle: MuscleGroup
    var secondary: [MuscleGroup] = []
    var technique: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let animation {
                        ExerciseAnimationView(animation: animation)
                            .padding(12)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line, lineWidth: 0.5))
                        Text("Tippen pausiert die Animation. Rosé = Zielmuskel.").font(.caption).foregroundStyle(Theme.muted)
                    }
                    HStack(spacing: 6) {
                        Pill(text: muscle.label)
                        ForEach(secondary) { Pill(text: $0.label, color: Theme.beige, ink: Theme.muted) }
                    }
                    if !technique.isEmpty {
                        Text("Ausführung").font(Theme.serif(.headline))
                        Text(technique).font(.body).foregroundStyle(Theme.ink)
                    }
                    Button {
                        Router.shared.coachRequest = CoachRequest(mode: "technique", label: "Erkläre mir \(name)", exerciseName: name)
                        Router.shared.tab = .coach
                        WorkoutManager.shared.showActive = false
                        dismiss()
                    } label: { Label("Coach nach Technik-Tipps fragen", systemImage: "sparkles") }
                        .buttonStyle(SoftButtonStyle())
                }
                .padding(16)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
    }
}
