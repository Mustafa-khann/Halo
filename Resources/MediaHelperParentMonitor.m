#import <Foundation/Foundation.h>
#include <unistd.h>

// The stream should also exit if Halo crashes or is force quit.
__attribute__((constructor)) static void watchHaloParent(void) {
    const char *value = getenv("HALO_MEDIA_PARENT_PID");
    if (!value) return;
    const pid_t expectedParent = (pid_t)strtol(value, NULL, 10);
    if (expectedParent <= 1 || getppid() != expectedParent) return;
    static dispatch_source_t watchdog;
    watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                      dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
                              3 * NSEC_PER_SEC, NSEC_PER_SEC);
    dispatch_source_set_event_handler(watchdog, ^{
        if (getppid() != expectedParent) exit(0);
    });
    dispatch_resume(watchdog);
}
