// App-side Darwin notifications are hints, not authority to block UIKit events.
// Pure C so the exact policy used by the hook can be regression-tested on Linux.
#ifndef KAYOKO_APP_TOUCH_POLICY_H
#define KAYOKO_APP_TOUCH_POLICY_H
#include <stdbool.h>

typedef struct {
    bool panelVisible;
} KayokoAppTouchState;

static inline void KayokoAppTouchReset(KayokoAppTouchState *state) {
    state->panelVisible = false;
}

static inline void KayokoAppTouchDidShow(KayokoAppTouchState *state,
                                        bool enabled, bool active) {
    state->panelVisible = enabled && active;
}

// Hide request. The caller may consume this one outside tap to preserve the
// dismiss gesture, but must not let the hint suppress subsequent hit tests.
static inline bool KayokoAppTouchRequestHide(KayokoAppTouchState *state,
                                            bool enabled, bool active,
                                            bool outsidePanel) {
    if (!enabled || !active) {
        KayokoAppTouchReset(state);
        return false;
    }
    if (!state->panelVisible || !outsidePanel) return false;
    KayokoAppTouchReset(state);
    return true;
}
#endif
