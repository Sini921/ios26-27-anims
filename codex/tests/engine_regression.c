#include <assert.h>
#include <stdio.h>
#include "../CodexGenie27/GenieEngine.h"

static void same(const G27Genie *a, const G27Genie *b) {
    assert(fabs(a->b - b->b) < 1e-10);
    for (int i = 0; i < G27_V; i++)
        for (int j = 0; j < 2; j++) {
            assert(fabs(a->p[i][j] - b->p[i][j]) < 1e-10);
            assert(fabs(a->v[i][j] - b->v[i][j]) < 1e-9);
        }
}

int main(void) {
    for (int close = 0; close < 2; close++) {
        for (int y = 118; y <= 865; y += 249) {
            G27Genie a, b;
            G27GenieStart(&a, close, 67, y, 64, 430, 932, close ? .336 : .24, 1.0);
            b = a;
            G27GenieStep(&a, .2);
            for (int i = 0; i < 24; i++) G27GenieStep(&b, 1.0/120);
            same(&a, &b);
            // Retargeting at unchanged icon geometry preserves position and velocity.
            G27Genie before = a;
            G27GenieRetarget(&a, !close, 67, y, 64, 430, 932, close ? .24 : .336, 1.0);
            same(&a, &before);
            b = a;
            G27GenieStep(&a, .15);
            for (int i = 0; i < 9; i++) G27GenieStep(&b, 1.0/60);
            same(&a, &b);
            G27GenieStep(&a, 5);
            assert(G27GenieSettled(&a));
            double xy[G27_V][2];
            G27GenieMesh(&a, a.b, xy);
            for (int i = 0; i < G27_V; i++) {
                assert(fabs(xy[i][0] - (i%3)/2.0) < 1e-8);
                assert(fabs(xy[i][1] - (i/3)/2.0) < 1e-8);
            }
            G27GenieStart(&a, close, 67, y, 64, 430, 932, .336, 1.0);
            b = a;
            for (int i = 0; i < 35; i++) {
                double dt = i == 6 ? .08 : 1.0/120;
                G27GenieStep(&b, dt);
                G27GenieFollowBounds(&a, b.b, dt);
                same(&a, &b);
            }
        }
    }
    puts("PASS: 60/120Hz invariance, dropped frames, continuous reversal, crop synchronization, settled identity");
}
