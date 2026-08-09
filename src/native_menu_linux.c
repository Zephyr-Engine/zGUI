#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef void GtkWidget;
typedef void (*NativeCallback)(void *, uint64_t);
typedef struct Action Action;
typedef struct NativeMenu {
    GtkWidget *window;
    GtkWidget *bar;
    GtkWidget *socket;
    NativeCallback callback;
    void *context;
    Action *actions;
} NativeMenu;
struct Action { NativeMenu *owner; uint64_t id; Action *next; };

static void *gtk_lib;
static void *gobject_lib;
static int loaded;
static int (*gtk_init_check_fn)(int *, char ***);
static GtkWidget *(*gtk_window_new_fn)(int);
static void (*gtk_window_set_title_fn)(void *, const char *);
static void (*gtk_window_maximize_fn)(void *);
static void (*gtk_window_set_titlebar_fn)(void *, void *);
static GtkWidget *(*gtk_header_bar_new_fn)(void);
static void (*gtk_header_bar_set_show_close_button_fn)(void *, int);
static void (*gtk_header_bar_pack_start_fn)(void *, void *);
static GtkWidget *(*gtk_box_new_fn)(int, int);
static void (*gtk_box_pack_start_fn)(void *, void *, int, int, unsigned int);
static GtkWidget *(*gtk_menu_bar_new_fn)(void);
static GtkWidget *(*gtk_menu_item_new_with_label_fn)(const char *);
static GtkWidget *(*gtk_menu_new_fn)(void);
static void (*gtk_menu_item_set_submenu_fn)(void *, void *);
static void (*gtk_menu_shell_append_fn)(void *, void *);
static GtkWidget *(*gtk_socket_new_fn)(void);
static void (*gtk_socket_add_id_fn)(void *, unsigned long);
static void (*gtk_container_add_fn)(void *, void *);
static void (*gtk_widget_show_all_fn)(void *);
static void (*gtk_widget_destroy_fn)(void *);
static int (*gtk_widget_get_allocated_width_fn)(void *);
static int (*gtk_events_pending_fn)(void);
static int (*gtk_main_iteration_do_fn)(int);
static unsigned long (*g_signal_connect_data_fn)(void *, const char *, void *, void *, void *, int);

static int load_gtk(void) {
    if (loaded) return gtk_lib != NULL;
    loaded = 1;
    /* GtkSocket embeds an X11 child window, so both toolkits must use X11.
       On a Wayland desktop this selects the compositor's XWayland bridge. */
    setenv("GDK_BACKEND", "x11", 1);
    gtk_lib = dlopen("libgtk-3.so.0", RTLD_NOW | RTLD_GLOBAL);
    gobject_lib = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!gtk_lib || !gobject_lib) return 0;
#define LOAD(lib, name) do { *(void **)(&name##_fn) = dlsym(lib, #name); if (!name##_fn) return 0; } while (0)
    LOAD(gtk_lib, gtk_init_check); LOAD(gtk_lib, gtk_window_new); LOAD(gtk_lib, gtk_window_set_title); LOAD(gtk_lib, gtk_window_maximize); LOAD(gtk_lib, gtk_window_set_titlebar);
    LOAD(gtk_lib, gtk_header_bar_new); LOAD(gtk_lib, gtk_header_bar_set_show_close_button); LOAD(gtk_lib, gtk_header_bar_pack_start);
    LOAD(gtk_lib, gtk_box_new); LOAD(gtk_lib, gtk_box_pack_start); LOAD(gtk_lib, gtk_menu_bar_new); LOAD(gtk_lib, gtk_menu_item_new_with_label);
    LOAD(gtk_lib, gtk_menu_new); LOAD(gtk_lib, gtk_menu_item_set_submenu); LOAD(gtk_lib, gtk_menu_shell_append); LOAD(gtk_lib, gtk_socket_new);
    LOAD(gtk_lib, gtk_socket_add_id); LOAD(gtk_lib, gtk_container_add); LOAD(gtk_lib, gtk_widget_show_all); LOAD(gtk_lib, gtk_widget_destroy); LOAD(gtk_lib, gtk_widget_get_allocated_width);
    LOAD(gtk_lib, gtk_events_pending); LOAD(gtk_lib, gtk_main_iteration_do); LOAD(gobject_lib, g_signal_connect_data);
#undef LOAD
    return 1;
}

static char *copy_string(const char *value, size_t length) { char *result = malloc(length + 1); if (!result) return NULL; memcpy(result, value, length); result[length] = 0; return result; }
static void activate(void *widget, void *data) { (void)widget; Action *action = data; action->owner->callback(action->owner->context, action->id); }
static void window_destroyed(void *widget, void *data) { (void)widget; NativeMenu *native = data; native->window = NULL; native->socket = NULL; native->callback(native->context, UINT64_MAX); }

void *zgui_native_menu_create(uintptr_t child_xid, const char *title, size_t title_len, void *context, NativeCallback callback) {
    if (!child_xid || !callback || !load_gtk() || !gtk_init_check_fn(NULL, NULL)) return NULL;
    NativeMenu *native = calloc(1, sizeof(*native)); if (!native) return NULL;
    char *window_title = copy_string(title, title_len); if (!window_title) { free(native); return NULL; }
    native->window = gtk_window_new_fn(0);
    GtkWidget *box = gtk_box_new_fn(1, 0), *bar = gtk_menu_bar_new_fn(), *header = gtk_header_bar_new_fn(), *socket = gtk_socket_new_fn();
    native->callback = callback; native->context = context;
    gtk_window_set_title_fn(native->window, window_title); free(window_title);
    gtk_header_bar_set_show_close_button_fn(header, 1); gtk_header_bar_pack_start_fn(header, bar); gtk_window_set_titlebar_fn(native->window, header);
    gtk_box_pack_start_fn(box, socket, 1, 1, 0); gtk_container_add_fn(native->window, box);
    g_signal_connect_data_fn(native->window, "destroy", window_destroyed, native, NULL, 0);
    gtk_window_maximize_fn(native->window); gtk_widget_show_all_fn(native->window); gtk_socket_add_id_fn(socket, (unsigned long)child_xid);
    native->bar = bar;
    native->socket = socket;
    return native;
}
void *zgui_native_menu_add_menu(void *handle, const char *label, size_t len) {
    NativeMenu *native = handle; if (!native) return NULL; GtkWidget *bar = native->bar;
    char *text = copy_string(label, len); if (!text) return NULL; GtkWidget *item = gtk_menu_item_new_with_label_fn(text); free(text);
    GtkWidget *menu = gtk_menu_new_fn(); gtk_menu_item_set_submenu_fn(item, menu); gtk_menu_shell_append_fn(bar, item); gtk_widget_show_all_fn(item); return menu;
}
int zgui_native_menu_add_item(void *handle, void *menu, const char *label, size_t len, uint64_t id) {
    NativeMenu *native = handle; if (!native || !menu) return 0; char *text = copy_string(label, len); if (!text) return 0;
    GtkWidget *item = gtk_menu_item_new_with_label_fn(text); free(text); Action *action = malloc(sizeof(*action)); if (!action) return 0;
    action->owner = native; action->id = id; action->next = NULL; g_signal_connect_data_fn(item, "activate", activate, action, NULL, 0); gtk_menu_shell_append_fn(menu, item); gtk_widget_show_all_fn(item); return 1;
}
void zgui_native_menu_poll(void *handle) { (void)handle; if (!loaded || !gtk_events_pending_fn) return; while (gtk_events_pending_fn()) gtk_main_iteration_do_fn(0); }
int zgui_native_menu_content_width(void *handle) { NativeMenu *native = handle; return native && native->socket ? gtk_widget_get_allocated_width_fn(native->socket) : 0; }
void zgui_native_menu_destroy(void *handle) { NativeMenu *native = handle; if (!native) return; if (native->window) gtk_widget_destroy_fn(native->window); free(native); }
