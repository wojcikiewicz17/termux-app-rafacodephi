#include "rafaelia_toroidal_inference.h"

#include <math.h>

#define RAFAELIA_PI 3.14159265358979323846

static double wrap01(double value) {
    double wrapped = fmod(value, 1.0);
    if (wrapped < 0.0) wrapped += 1.0;
    return wrapped;
}

double rafaelia_sphere_volume(double radius) {
    if (radius < 0.0) return -1.0;
    return (4.0 / 3.0) * RAFAELIA_PI * radius * radius * radius;
}

double rafaelia_torus_volume(double major_radius, double minor_radius) {
    if (major_radius <= 0.0 || minor_radius <= 0.0) return -1.0;
    return 2.0 * RAFAELIA_PI * RAFAELIA_PI * major_radius * minor_radius * minor_radius;
}

rafaelia_state7_t rafaelia_toroidal_map(double data, double entropy, double hash_norm, double state_norm) {
    rafaelia_state7_t s;
    double base = wrap01(data + 0.5 * entropy + 0.25 * hash_norm + 0.125 * state_norm);
    s.u = wrap01(base);
    s.v = wrap01(base + entropy);
    s.psi = wrap01(base + hash_norm);
    s.chi = wrap01(base + state_norm);
    s.rho = wrap01((data * hash_norm) + entropy);
    s.delta = wrap01((1.0 - entropy) * state_norm);
    s.sigma = wrap01((s.u + s.v + s.psi + s.chi + s.rho + s.delta) / 6.0);
    return s;
}

void rafaelia_update_coherence_entropy(double c_t, double h_t,
                                       double c_in, double h_in,
                                       double alpha,
                                       double *c_next, double *h_next) {
    if (!c_next || !h_next) return;
    *c_next = (1.0 - alpha) * c_t + alpha * c_in;
    *h_next = (1.0 - alpha) * h_t + alpha * h_in;
}

double rafaelia_phi_ctrl(double coherence, double entropy) {
    return (1.0 - entropy) * coherence;
}

int rafaelia_pulse_stats(const double *samples, size_t len, rafaelia_pulse_stats_t *out) {
    if (!samples || !out || len == 0) return -1;
    double min = samples[0], max = samples[0], sum = 0.0;
    for (size_t i = 0; i < len; i++) {
        if (samples[i] < min) min = samples[i];
        if (samples[i] > max) max = samples[i];
        sum += samples[i];
    }
    out->min = min;
    out->max = max;
    out->median = sum / (double)len;
    return 0;
}
