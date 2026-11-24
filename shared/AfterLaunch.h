#pragma once

#import <dispatch/dispatch.h>
#include <stdio.h>
#include <unistd.h>

// Install feature hooks once after SpringBoard's launch callback returns.
static void CG27AfterLaunch(dispatch_block_t action) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ dispatch_async(dispatch_get_main_queue(), action); });
}

#ifdef CG27_STARTUP_LOG
static void CG27StartupTrace(const char *stage) {
    FILE *log = fopen(CG27_STARTUP_LOG, "a");
    if (!log) return;
    fprintf(log, "pid %d: %s\n", getpid(), stage);
    fclose(log);
}
#else
#define CG27StartupTrace(stage) ((void)0)
#endif
