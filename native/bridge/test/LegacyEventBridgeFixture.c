#include <string.h>

#include "dart_appkit.h"

uint32_t da_abi_version(void) { return DA_ABI_VERSION; }

const char* da_status_name(int32_t status) {
  (void)status;
  return "fixture";
}

void da_get_last_error(DaError* out_error) {
  static const char message[] = "legacy fixture failure";
  if (out_error != NULL) {
    out_error->code = DA_STATUS_INTERNAL_ERROR;
    out_error->message = message;
    out_error->message_length = strlen(message);
  }
}

int32_t da_application_set_event_port(int64_t dart_port) {
  return dart_port > 0 ? DA_STATUS_OK : DA_STATUS_INVALID_ARGUMENT;
}

int32_t da_application_terminate(void) { return DA_STATUS_OK; }

int32_t da_application_open_external_url(const char* url, size_t url_length,
                                         int32_t* out_opened) {
  (void)url;
  (void)url_length;
  if (out_opened != NULL) {
    *out_opened = 0;
  }
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_create(DaRect frame, const char* title, size_t title_length,
                         DaHandle* out_window) {
  (void)frame;
  (void)title;
  (void)title_length;
  if (out_window != NULL) {
    *out_window = 0;
  }
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_show(DaHandle window) {
  (void)window;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_close(DaHandle window) {
  (void)window;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_set_title(DaHandle window, const char* title,
                            size_t title_length) {
  (void)window;
  (void)title;
  (void)title_length;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_set_tab_color(DaHandle window, int32_t has_color,
                                double red, double green, double blue,
                                double alpha) {
  (void)window;
  (void)has_color;
  (void)red;
  (void)green;
  (void)blue;
  (void)alpha;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_text_view_create(DaHandle* out_view) {
  if (out_view != NULL) {
    *out_view = 0;
  }
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_text_view_set_text(DaHandle view, const char* text,
                              size_t text_length) {
  (void)view;
  (void)text;
  (void)text_length;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_window_set_content_view(DaHandle window, DaHandle view) {
  (void)window;
  (void)view;
  return DA_STATUS_INTERNAL_ERROR;
}

int32_t da_release(DaHandle handle) {
  (void)handle;
  return DA_STATUS_INTERNAL_ERROR;
}

void da_release_finalizer(void* token) { (void)token; }

int32_t da_debug_is_main_thread(int32_t* out_is_main_thread) {
  if (out_is_main_thread == NULL) {
    return DA_STATUS_INVALID_ARGUMENT;
  }
  *out_is_main_thread = 1;
  return DA_STATUS_OK;
}

int32_t da_debug_live_object_count(uint64_t* out_count) {
  if (out_count == NULL) {
    return DA_STATUS_INVALID_ARGUMENT;
  }
  *out_count = 0;
  return DA_STATUS_OK;
}
