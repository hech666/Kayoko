// The helper's visibility hint remains active until Core confirms the hide animation
// has completed. This keeps repeated hitTest calls for the same dismiss tap from
// leaking it through to the app (which can dismiss the active keyboard). A hidden,
// inactive, or disabled session still clears the hint immediately.
#ifndef KAYOKO_APP_TOUCH_POLICY_H
#define KAYOKO_APP_TOUCH_POLICY_H
#include <stdbool.h>

typedef struct {
    bool panelVisible;
    bool dismissPending;
} KayokoAppTouchState;

typedef enum {
    KayokoAppTouchPass = 0,
    KayokoAppTouchSuppress = 1,
    KayokoAppTouchDismiss = 2
} KayokoAppTouchDecision;

static inline void KayokoAppTouchReset(KayokoAppTouchState *state) {
    state->panelVisible = false;
    state->dismissPending = false;
}

static inline void KayokoAppTouchDidShow(KayokoAppTouchState *state,
                                        bool enabled, bool active) {
    state->panelVisible = enabled && active;
    state->dismissPending = false;
}

static inline KayokoAppTouchDecision KayokoAppTouchRequestHide(
                                            KayokoAppTouchState *state,
                                            bool enabled, bool active,
                                            bool outsidePanel) {
    if (!enabled || !active) {
        KayokoAppTouchReset(state);
        return KayokoAppTouchPass;
    }
    if (!state->panelVisible || !outsidePanel) return KayokoAppTouchPass;
    if (state->dismissPending) return KayokoAppTouchSuppress;

    // UIKit can ask multiple windows to hit-test the same touch. Keep consuming
    // it until Core confirms dismissal, without repeatedly posting hide requests.
    state->dismissPending = true;
    return KayokoAppTouchDismiss;
}
#endif
