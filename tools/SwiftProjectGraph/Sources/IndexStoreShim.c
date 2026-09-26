#include <stdbool.h>
#include <stddef.h>

typedef void *indexstore_t;
typedef struct {
  const char *data;
  size_t length;
} indexstore_string_ref_t;

typedef bool (*indexstore_unit_applier_t)(void *, indexstore_string_ref_t);
extern bool indexstore_store_units_apply_f(indexstore_t, unsigned, void *,
                                            indexstore_unit_applier_t);

typedef bool (*spg_unit_applier_t)(void *, const char *, size_t);
struct spg_unit_context {
  void *context;
  spg_unit_applier_t callback;
};

static bool spg_forward_unit(void *raw, indexstore_string_ref_t unit) {
  struct spg_unit_context *bridge = raw;
  return bridge->callback(bridge->context, unit.data, unit.length);
}

bool spg_store_units(indexstore_t store, void *context,
                     spg_unit_applier_t callback) {
  struct spg_unit_context bridge = {context, callback};
  return indexstore_store_units_apply_f(store, 1, &bridge, spg_forward_unit);
}
