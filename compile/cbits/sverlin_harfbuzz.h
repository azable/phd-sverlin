#ifndef SVERLIN_HARFBUZZ_H
#define SVERLIN_HARFBUZZ_H

#include <stddef.h>
#include <stdint.h>

typedef struct sverlin_hb_shape_result sverlin_hb_shape_result;

enum sverlin_hb_status {
  SVERLIN_HB_OK = 0,
  SVERLIN_HB_INVALID_ARGUMENT = 1,
  SVERLIN_HB_INVALID_FONT = 2,
  SVERLIN_HB_ALLOCATION_FAILURE = 3,
  SVERLIN_HB_SHAPING_FAILURE = 4
};

int sverlin_hb_shape(const uint8_t *font_data,
                     size_t font_length,
                     const char *utf8,
                     int utf8_length,
                     float weight,
                     int disable_ligatures,
                     sverlin_hb_shape_result **out_result);

void sverlin_hb_shape_destroy(sverlin_hb_shape_result *result);

const char *sverlin_hb_version_string(void);

uint32_t sverlin_hb_upem(const sverlin_hb_shape_result *result);
int32_t sverlin_hb_ascender(const sverlin_hb_shape_result *result);
int32_t sverlin_hb_descender(const sverlin_hb_shape_result *result);
int32_t sverlin_hb_line_gap(const sverlin_hb_shape_result *result);
uint32_t sverlin_hb_script_tag(const sverlin_hb_shape_result *result);
int sverlin_hb_is_rtl(const sverlin_hb_shape_result *result);
unsigned int sverlin_hb_glyph_count(const sverlin_hb_shape_result *result);

uint32_t sverlin_hb_glyph_id(const sverlin_hb_shape_result *result,
                             unsigned int index);
uint32_t sverlin_hb_glyph_cluster(const sverlin_hb_shape_result *result,
                                  unsigned int index);
int32_t sverlin_hb_glyph_x_advance(const sverlin_hb_shape_result *result,
                                   unsigned int index);
int32_t sverlin_hb_glyph_y_advance(const sverlin_hb_shape_result *result,
                                   unsigned int index);
int32_t sverlin_hb_glyph_x_offset(const sverlin_hb_shape_result *result,
                                  unsigned int index);
int32_t sverlin_hb_glyph_y_offset(const sverlin_hb_shape_result *result,
                                  unsigned int index);
int32_t sverlin_hb_glyph_x_bearing(const sverlin_hb_shape_result *result,
                                   unsigned int index);
int32_t sverlin_hb_glyph_y_bearing(const sverlin_hb_shape_result *result,
                                   unsigned int index);
int32_t sverlin_hb_glyph_width(const sverlin_hb_shape_result *result,
                               unsigned int index);
int32_t sverlin_hb_glyph_height(const sverlin_hb_shape_result *result,
                                unsigned int index);

#endif
