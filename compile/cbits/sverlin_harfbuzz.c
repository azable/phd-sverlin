#include "sverlin_harfbuzz.h"

#include <harfbuzz/hb-ot.h>
#include <harfbuzz/hb.h>
#include <stdlib.h>

typedef struct sverlin_hb_glyph {
  uint32_t glyph_id;
  uint32_t cluster;
  int32_t x_advance;
  int32_t y_advance;
  int32_t x_offset;
  int32_t y_offset;
  int32_t x_bearing;
  int32_t y_bearing;
  int32_t width;
  int32_t height;
} sverlin_hb_glyph;

struct sverlin_hb_shape_result {
  uint32_t upem;
  int32_t ascender;
  int32_t descender;
  int32_t line_gap;
  uint32_t script_tag;
  int is_rtl;
  unsigned int glyph_count;
  sverlin_hb_glyph *glyphs;
};

static void destroy_shape_objects(hb_buffer_t *buffer,
                                  hb_font_t *font,
                                  hb_face_t *face,
                                  hb_blob_t *blob) {
  if (buffer != NULL) {
    hb_buffer_destroy(buffer);
  }
  if (font != NULL) {
    hb_font_destroy(font);
  }
  if (face != NULL) {
    hb_face_destroy(face);
  }
  if (blob != NULL) {
    hb_blob_destroy(blob);
  }
}

int sverlin_hb_shape(const uint8_t *font_data,
                     size_t font_length,
                     const char *utf8,
                     int utf8_length,
                     float weight,
                     int disable_ligatures,
                     sverlin_hb_shape_result **out_result) {
  hb_blob_t *blob = NULL;
  hb_face_t *face = NULL;
  hb_font_t *font = NULL;
  hb_buffer_t *buffer = NULL;
  sverlin_hb_shape_result *result = NULL;
  unsigned int glyph_count = 0;

  if (font_data == NULL || font_length == 0 || utf8 == NULL ||
      utf8_length < 0 || out_result == NULL) {
    return SVERLIN_HB_INVALID_ARGUMENT;
  }
  *out_result = NULL;

  blob = hb_blob_create((const char *)font_data,
                        (unsigned int)font_length,
                        HB_MEMORY_MODE_DUPLICATE,
                        NULL,
                        NULL);
  face = hb_face_create(blob, 0);
  if (blob == hb_blob_get_empty() || face == hb_face_get_empty() ||
      hb_face_get_glyph_count(face) == 0) {
    destroy_shape_objects(NULL, NULL, face, blob);
    return SVERLIN_HB_INVALID_FONT;
  }

  font = hb_font_create(face);
  buffer = hb_buffer_create();
  if (font == hb_font_get_empty() || buffer == hb_buffer_get_empty()) {
    destroy_shape_objects(buffer, font, face, blob);
    return SVERLIN_HB_ALLOCATION_FAILURE;
  }

  const uint32_t upem = hb_face_get_upem(face);
  hb_ot_font_set_funcs(font);
  hb_font_set_scale(font, (int)upem, (int)upem);
  if (weight > 0.0f) {
    hb_variation_t variation = {HB_TAG('w', 'g', 'h', 't'), weight};
    hb_font_set_variations(font, &variation, 1);
  }

  hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_MONOTONE_CHARACTERS);
  hb_buffer_add_utf8(buffer, utf8, utf8_length, 0, utf8_length);
  hb_buffer_guess_segment_properties(buffer);
  hb_buffer_set_language(buffer, hb_language_from_string("und", -1));

  hb_feature_t typography_features[2];
  unsigned int feature_count = 0;
  if (disable_ligatures != 0) {
    typography_features[0] = (hb_feature_t){HB_TAG('l', 'i', 'g', 'a'), 0,
                                            HB_FEATURE_GLOBAL_START,
                                            HB_FEATURE_GLOBAL_END};
    typography_features[1] = (hb_feature_t){HB_TAG('c', 'a', 'l', 't'), 0,
                                            HB_FEATURE_GLOBAL_START,
                                            HB_FEATURE_GLOBAL_END};
    feature_count = 2;
  }
  hb_shape(font,
           buffer,
           feature_count == 0 ? NULL : typography_features,
           feature_count);

  hb_glyph_info_t *infos = hb_buffer_get_glyph_infos(buffer, &glyph_count);
  hb_glyph_position_t *positions = hb_buffer_get_glyph_positions(buffer, NULL);
  if ((glyph_count > 0 && (infos == NULL || positions == NULL)) ||
      !hb_buffer_allocation_successful(buffer)) {
    destroy_shape_objects(buffer, font, face, blob);
    return SVERLIN_HB_SHAPING_FAILURE;
  }

  result = (sverlin_hb_shape_result *)calloc(1, sizeof(*result));
  if (result == NULL) {
    destroy_shape_objects(buffer, font, face, blob);
    return SVERLIN_HB_ALLOCATION_FAILURE;
  }
  if (glyph_count > 0) {
    result->glyphs =
        (sverlin_hb_glyph *)calloc(glyph_count, sizeof(*result->glyphs));
    if (result->glyphs == NULL) {
      free(result);
      destroy_shape_objects(buffer, font, face, blob);
      return SVERLIN_HB_ALLOCATION_FAILURE;
    }
  }

  hb_font_extents_t font_extents = {0, 0, 0};
  const hb_direction_t direction = hb_buffer_get_direction(buffer);
  (void)hb_font_get_extents_for_direction(font, direction, &font_extents);
  result->upem = upem;
  result->ascender = font_extents.ascender;
  result->descender = font_extents.descender;
  result->line_gap = font_extents.line_gap;
  result->script_tag = hb_script_to_iso15924_tag(hb_buffer_get_script(buffer));
  result->is_rtl = HB_DIRECTION_IS_BACKWARD(direction) ? 1 : 0;
  result->glyph_count = glyph_count;

  for (unsigned int index = 0; index < glyph_count; ++index) {
    hb_glyph_extents_t glyph_extents = {0, 0, 0, 0};
    (void)hb_font_get_glyph_extents(font, infos[index].codepoint, &glyph_extents);
    result->glyphs[index] = (sverlin_hb_glyph){
        infos[index].codepoint,
        infos[index].cluster,
        positions[index].x_advance,
        positions[index].y_advance,
        positions[index].x_offset,
        positions[index].y_offset,
        glyph_extents.x_bearing,
        glyph_extents.y_bearing,
        glyph_extents.width,
        glyph_extents.height};
  }

  destroy_shape_objects(buffer, font, face, blob);
  *out_result = result;
  return SVERLIN_HB_OK;
}

void sverlin_hb_shape_destroy(sverlin_hb_shape_result *result) {
  if (result != NULL) {
    free(result->glyphs);
    free(result);
  }
}

const char *sverlin_hb_version_string(void) { return hb_version_string(); }

uint32_t sverlin_hb_upem(const sverlin_hb_shape_result *result) {
  return result->upem;
}
int32_t sverlin_hb_ascender(const sverlin_hb_shape_result *result) {
  return result->ascender;
}
int32_t sverlin_hb_descender(const sverlin_hb_shape_result *result) {
  return result->descender;
}
int32_t sverlin_hb_line_gap(const sverlin_hb_shape_result *result) {
  return result->line_gap;
}
uint32_t sverlin_hb_script_tag(const sverlin_hb_shape_result *result) {
  return result->script_tag;
}
int sverlin_hb_is_rtl(const sverlin_hb_shape_result *result) {
  return result->is_rtl;
}
unsigned int sverlin_hb_glyph_count(const sverlin_hb_shape_result *result) {
  return result->glyph_count;
}

#define SVERLIN_GLYPH_ACCESSOR(name, field)                                      \
  int32_t name(const sverlin_hb_shape_result *result, unsigned int index) {      \
    return result->glyphs[index].field;                                           \
  }

uint32_t sverlin_hb_glyph_id(const sverlin_hb_shape_result *result,
                             unsigned int index) {
  return result->glyphs[index].glyph_id;
}
uint32_t sverlin_hb_glyph_cluster(const sverlin_hb_shape_result *result,
                                  unsigned int index) {
  return result->glyphs[index].cluster;
}
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_x_advance, x_advance)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_y_advance, y_advance)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_x_offset, x_offset)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_y_offset, y_offset)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_x_bearing, x_bearing)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_y_bearing, y_bearing)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_width, width)
SVERLIN_GLYPH_ACCESSOR(sverlin_hb_glyph_height, height)

#undef SVERLIN_GLYPH_ACCESSOR
