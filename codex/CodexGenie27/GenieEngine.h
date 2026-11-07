// Port of the iOS 27.0 SpringBoard genie (SBSwitcherGenieEffectView / SBSwitcherGenieAttributes, iPhone path).
// Decoded from -[SBSwitcherGenieEffectView _performGenieWithAttributes:mode:completion:] block_invoke_3 and
// -_updateGenieMeshTransformForPresentationLayer:properties:boundsProperty:attributes:; checked against the
// recorded iOS 27 meshes (logs/mesh_frames.log, rms error 0.0003-0.001 of the window size; engine/check.py).
//
// Output is the 3x3 mesh in the normalized space of the visible crop (the iOS 16 item container), i.e. the
// iOS 27 destination point divided by the crop rect.
#pragma once
#include <math.h>
#include <stdbool.h>

#define G27_N 3                     // vertices per side (rows = columns = 2)
#define G27_V (G27_N * G27_N)

static const double G27GenieScale = 0.4;     // SBSwitcherGenieAttributes.genieScale
static const double G27Multiplier = 0.5;     // .multiplier (x and y)

typedef struct {
    double p[G27_V][2], v[G27_V][2];          // vertex property values / velocities
    double target[G27_V][2], response[G27_V];
    double b, bv, bTarget, bResponse;         // bounds progress: 0 = window, 1 = minimized square
    double zeta;                              // layoutSettings.dampingRatio (all genie springs)
    double px;                                // minimizedProgress.x
    double ms;                                // minimizedScale
    bool active;                              // target state is minimized (closing)
} G27Genie;

// Fluid spring (UIKit/SBFFluidBehaviorSettings): stiffness (2π/response)², damping 4π·ratio/response, mass 1.
// Exact solution for any damping ratio (the swipe-close genie uses the home-gesture layout spring, ratio 1.1).
static inline void G27SpringStep(double *x, double *v, double target, double response, double zeta, double dt) {
    if (!isfinite(dt) || dt <= 0 || !isfinite(response) || response <= 0) return;
    double w = 2 * M_PI / response, x0 = *x - target, v0 = *v;
    if (!isfinite(zeta) || zeta <= 0) zeta = 1;
    if (fabs(zeta - 1) < 1e-6) {
        double c = v0 + w * x0, decay = exp(-w * dt);
        *x = target + (x0 + c * dt) * decay;
        *v = (v0 - w * c * dt) * decay;
    } else if (zeta < 1) {
        double wd = w * sqrt(1 - zeta * zeta), a = zeta * w, decay = exp(-a * dt);
        double B = (v0 + a * x0) / wd, cs = cos(wd * dt), sn = sin(wd * dt);
        *x = target + decay * (x0 * cs + B * sn);
        *v = decay * ((B * wd - a * x0) * cs - (x0 * wd + a * B) * sn);
    } else {
        double s = sqrt(zeta * zeta - 1), r1 = -w * (zeta - s), r2 = -w * (zeta + s);
        double c2 = (v0 - r1 * x0) / (r2 - r1), c1 = x0 - c2;
        double e1 = exp(r1 * dt), e2 = exp(r2 * dt);
        *x = target + c1 * e1 + c2 * e2;
        *v = c1 * r1 * e1 + c2 * r2 * e2;
    }
}

static inline double G27Clamp(double x, double lo, double hi) { return x < lo ? lo : x > hi ? hi : x; }

// iconCenter / iconWidth / window size in screen points (window centred on screen).
// iconPosition (genieAttributesForAppLayout) = (icon centre x − icon width / 2, icon centre y).
// genieAmount (iPhone): gy = clamp(2·(iconY − windowTop)/H − 1), ×0.75 when above the centre; gx = 0.
static inline void G27GenieRetarget(G27Genie *g, bool active, double iconCX, double iconCY, double iconW,
                                    double W, double H, double response, double zeta) {
    double px = G27Clamp((iconCX - iconW / 2) / W, 0, 1);
    double raw = G27Clamp(2 * iconCY / H - 1, -1, 1);
    double gy = raw >= 0 ? raw : 0.75 * raw;
    double gAttr = active ? gy : -gy;                 // genieAmount of the target attributes
    double gE = active ? gAttr : -gAttr;              // block_invoke_3: active ? g : -g  (== gy)
    double sp = active ? 1 - G27GenieScale : 0;       // scaleProgress
    double mpx = active ? px : 0.5, mpy = 0.5;        // minimizedProgress
    g->px = px;
    g->ms = G27Clamp(iconW / W / G27GenieScale, 0.05, 0.95);
    g->active = active;
    for (int i = 0; i < G27_N; i++) {
        double r = (double)i / (G27_N - 1);
        double w = gE >= 0 ? sqrt(r) : 1 - sqrt(1 - r);
        double resp = response * (1 + G27Multiplier * gAttr * (1 - 2 * w));
        for (int j = 0; j < G27_N; j++) {
            int k = i * G27_N + j;
            double c = (double)j / (G27_N - 1);
            g->target[k][0] = c + sp * (mpx - c);
            g->target[k][1] = r + sp * (mpy - r);
            g->response[k] = resp;
        }
    }
    g->bTarget = active ? 1 : 0;
    g->bResponse = response;
    g->zeta = zeta;
}

// Start at rest in the opposite state, then animate to `active`.
static inline void G27GenieStart(G27Genie *g, bool active, double iconCX, double iconCY, double iconW,
                                 double W, double H, double response, double zeta) {
    G27GenieRetarget(g, !active, iconCX, iconCY, iconW, W, H, response, zeta);
    for (int k = 0; k < G27_V; k++) {
        g->p[k][0] = g->target[k][0]; g->p[k][1] = g->target[k][1];
        g->v[k][0] = g->v[k][1] = 0;
    }
    g->b = g->bTarget; g->bv = 0;
    G27GenieRetarget(g, active, iconCX, iconCY, iconW, W, H, response, zeta);
}

static inline void G27GenieStep(G27Genie *g, double dt) {
    for (int k = 0; k < G27_V; k++)
        for (int a = 0; a < 2; a++)
            G27SpringStep(&g->p[k][a], &g->v[k][a], g->target[k][a], g->response[k], g->zeta, dt);
    G27SpringStep(&g->b, &g->bv, g->bTarget, g->bResponse, g->zeta, dt);
}

// Solve a single shared spring time for the measured crop. All vertices advance
// together, with no fixed 1ms steps or periodic catch-up frames. During reversal
// the bounds may initially travel away from the target; keep real time then.
static inline void G27GenieFollowBounds(G27Genie *g, double measured, double dt) {
    double direction = g->bTarget > 0.5 ? 1 : -1;
    if (!isfinite(measured) || fabs(measured - g->bTarget) < 0.001 ||
        g->bv * direction < -0.001) {
        G27GenieStep(g, dt);
        return;
    }
    if ((measured - g->b) * direction <= 0) {
        // Within a frame the crop may trail the engine slightly: wait for it.
        if (fabs(measured - g->b) < 0.02) return;
        // After a retarget the window spring keeps its old momentum, so the crop can sit far behind the
        // engine for several frames. Freezing there stalled the mesh while the window moved (visible hitch on
        // open-after-close); keep the vertices on real time and pin the bounds progress to the crop instead.
        G27GenieStep(g, dt);
        g->b = measured;
        return;
    }
    double lo = 0, hi = fmax(dt * 4, 0.1);
    double x = g->b, v = g->bv;
    G27SpringStep(&x, &v, g->bTarget, g->bResponse, g->zeta, hi);
    if ((x - measured) * direction < 0) { G27GenieStep(g, dt); return; }
    for (int i = 0; i < 44; i++) {
        double mid = (lo + hi) * 0.5;
        x = g->b; v = g->bv;
        G27SpringStep(&x, &v, g->bTarget, g->bResponse, g->zeta, mid);
        if ((x - measured) * direction < 0) lo = mid;
        else hi = mid;
    }
    G27GenieStep(g, (lo + hi) * 0.5);
}

static inline bool G27GenieSettled(const G27Genie *g) {
    double e = fabs(g->b - g->bTarget) + fabs(g->bv) * 0.01;
    for (int k = 0; k < G27_V; k++)
        for (int a = 0; a < 2; a++)
            e += fabs(g->p[k][a] - g->target[k][a]) + fabs(g->v[k][a]) * 0.01;
    return e < 0.002;
}

// Mesh for bounds progress b (pass g->b, or the value measured from the live crop).
// k = counter-scale; the grid is scaled by k about the centre vertex, and shifted by the counter offset
// (counterOffsetForSize: of the minimized square), which makes the minimized state the identity mesh.
static inline void G27GenieMesh(const G27Genie *g, double b, double out[G27_V][2]) {
    double ms = g->ms, gs = G27GenieScale, msgs = ms * gs;
    double k = (ms + (1 - ms) * (1 - b)) / (msgs + (1 - b) * (1 - msgs));
    double sp = 1 - gs;
    double counter = 0.5 - g->px + (1 - sp) * (g->px - 0.5);   // counterOffsetForSize / minimized width
    double off = counter * (k - 1) / (1 / gs - 1);
    const double *a = g->p[G27_V / 2];
    for (int q = 0; q < G27_V; q++) {
        out[q][0] = off + a[0] + (g->p[q][0] - a[0]) * k;
        out[q][1] = a[1] + (g->p[q][1] - a[1]) * k;
    }
}
