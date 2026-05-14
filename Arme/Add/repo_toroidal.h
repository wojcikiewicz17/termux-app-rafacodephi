#ifndef RAFAELIA_TOROIDAL_INFERENCE_H
#define RAFAELIA_TOROIDAL_INFERENCE_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    double u, v, psi, chi, rho, delta, sigma;
} rafaelia_state7_t;

typedef struct {
    double min;
    double median;
    double max;
} rafaelia_pulse_stats_t;

double rafaelia_sphere_volume(double radius);
double rafaelia_torus_volume(double major_radius, double minor_radius);

rafaelia_state7_t rafaelia_toroidal_map(double data, double entropy, double hash_norm, double state_norm);

void rafaelia_update_coherence_entropy(double c_t, double h_t,
                                       double c_in, double h_in,
                                       double alpha,
                                       double *c_next, double *h_next);

double rafaelia_phi_ctrl(double coherence, double entropy);

int rafaelia_pulse_stats(const double *samples, size_t len, rafaelia_pulse_stats_t *out);

#ifdef __cplusplus
}
#endif

#endif
