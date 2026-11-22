#pragma once
#include <math.h>
#include <stdbool.h>

#define G27_N 3
#define G27_V (G27_N * G27_N)

static inline double G27GenieScaleForGridClass(unsigned long gridClass) {
    return gridClass == 1 ? 1.0 / 1.75 : (gridClass >= 2 && gridClass <= 4 ? 1.0 / 1.25 : 1.0 / 2.5);
}

static inline double G27GenieScaleForIcon(double iconW, double iconH, double windowW) {
    if (iconW > windowW * 0.25 || iconH > windowW * 0.25) {
        bool small = iconW < windowW * 0.5 && iconH < windowW * 0.5 && fabs(iconW - iconH) < windowW * 0.08;
        return small ? 1.0 / 1.75 : 1.0 / 1.25;
    }
    return 1.0 / 2.5;
}

typedef struct {
    double p[G27_V][2], v[G27_V][2];
    double target[G27_V][2], response[G27_V];
    double b, bv, bTarget, bResponse;
    double zeta;
    double px;
    double ms;
    double gs;
    bool active;
} G27Genie;

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

static inline double G27ClosingSnapshotAlpha(double b) {
    double x = G27Clamp((1 - b - .25) / .35, 0, 1);
    if (x <= 0 || x >= 1) return x;
    double lo = 0, hi = 1, t = x;
    for (int i = 0; i < 32; i++) {
        t = (lo + hi) * .5;
        double u = 1 - t, bx = .75 * u * u * t + .75 * u * t * t + t * t * t;
        if (bx < x) lo = t; else hi = t;
    }
    double u = 1 - t, y = .3 * u * u * t + 3 * u * t * t + t * t * t;
    return G27Clamp(10 * y, 0, 1);
}

static inline void G27GenieRetargetWithScale(G27Genie *g, bool active, double iconCX, double iconCY, double iconW,
                                             double W, double H, double response, double zeta, double gs) {
    double px = G27Clamp((iconCX - iconW / 2) / W, 0, 1);
    double raw = G27Clamp(2 * iconCY / H - 1, -1, 1);
    double gy = raw >= 0 ? raw : 0.75 * raw;
    double gAttr = active ? gy : -gy;
    double gE = active ? gAttr : -gAttr;
    double sp = active ? 1 - gs : 0;
    double mpx = active ? px : 0.5, mpy = 0.5;
    g->px = px;
    g->gs = gs;
    g->ms = G27Clamp(iconW / W / gs, 0.05, 4.0);
    g->active = active;
    for (int i = 0; i < G27_N; i++) {
        double r = (double)i / (G27_N - 1);
        double w = gE >= 0 ? sqrt(r) : 1 - sqrt(1 - r);
        double multiplier = gs == 1.0 / 1.25 ? 0.25 : 0.5;
        double resp = response * (1 + multiplier * gAttr * (1 - 2 * w));
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

static inline void G27GenieRetarget(G27Genie *g, bool active, double iconCX, double iconCY, double iconW, double iconH,
                                    double W, double H, double response, double zeta) {
    G27GenieRetargetWithScale(g, active, iconCX, iconCY, iconW, W, H, response, zeta, G27GenieScaleForIcon(iconW, iconH, W));
}

static inline void G27GenieStartWithScale(G27Genie *g, bool active, double iconCX, double iconCY, double iconW,
                                          double W, double H, double response, double zeta, double gs) {
    G27GenieRetargetWithScale(g, !active, iconCX, iconCY, iconW, W, H, response, zeta, gs);
    for (int k = 0; k < G27_V; k++) {
        g->p[k][0] = g->target[k][0]; g->p[k][1] = g->target[k][1];
        g->v[k][0] = g->v[k][1] = 0;
    }
    g->b = g->bTarget; g->bv = 0;
    G27GenieRetargetWithScale(g, active, iconCX, iconCY, iconW, W, H, response, zeta, gs);
}

static inline void G27GenieStart(G27Genie *g, bool active, double iconCX, double iconCY, double iconW, double iconH,
                                 double W, double H, double response, double zeta) {
    G27GenieStartWithScale(g, active, iconCX, iconCY, iconW, W, H, response, zeta, G27GenieScaleForIcon(iconW, iconH, W));
}

static inline void G27GenieStep(G27Genie *g, double dt) {
    for (int k = 0; k < G27_V; k++)
        for (int a = 0; a < 2; a++)
            G27SpringStep(&g->p[k][a], &g->v[k][a], g->target[k][a], g->response[k], g->zeta, dt);
    G27SpringStep(&g->b, &g->bv, g->bTarget, g->bResponse, g->zeta, dt);
}

static inline void G27GenieFollowBounds(G27Genie *g, double measured, double dt) {
    double direction = g->bTarget > 0.5 ? 1 : -1;
    if (!isfinite(measured) || fabs(measured - g->bTarget) < 0.001 ||
        g->bv * direction < -0.001) {
        G27GenieStep(g, dt);
        return;
    }
    if ((measured - g->b) * direction <= 0) {
        if (fabs(measured - g->b) < 0.02) return;
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

static inline void G27GenieMesh(const G27Genie *g, double b, double out[G27_V][2]) {
    double ms = g->ms, gs = g->gs, msgs = ms * gs;
    double k = (ms + (1 - ms) * (1 - b)) / (msgs + (1 - b) * (1 - msgs));
    double sp = 1 - gs;
    double counter = 0.5 - g->px + (1 - sp) * (g->px - 0.5);
    double off = counter * (k - 1) / (1 / gs - 1);
    const double *a = g->p[G27_V / 2];
    for (int q = 0; q < G27_V; q++) {
        out[q][0] = off + a[0] + (g->p[q][0] - a[0]) * k;
        out[q][1] = a[1] + (g->p[q][1] - a[1]) * k;
    }
}
