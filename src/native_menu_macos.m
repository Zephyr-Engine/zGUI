#import <AppKit/AppKit.h>
#include <stdlib.h>

typedef void (*NativeCallback)(void *, unsigned long long);
typedef struct NativeMenu {
    NSMenu *main_menu;
    NativeCallback callback;
    void *context;
} NativeMenu;

@interface ZGuiMenuAction : NSObject {
@public NativeMenu *owner;
@public unsigned long long action_id;
}
- (void)activate:(id)sender;
@end

@implementation ZGuiMenuAction
- (void)activate:(id)sender {
    (void)sender;
    owner->callback(owner->context, action_id);
}
@end

void *zgui_native_menu_create(unsigned long long window_handle, const char *title, unsigned long title_len, void *context, NativeCallback callback) {
    (void)window_handle;
    if (!callback) return NULL;
    NativeMenu *native = calloc(1, sizeof(*native));
    if (!native) return NULL;
    native->callback = callback;
    native->context = context;
    [NSApplication sharedApplication];
    native->main_menu = [[NSMenu alloc] initWithTitle:@""];
    [[NSApplication sharedApplication] setMainMenu:native->main_menu];
    (void)title;
    (void)title_len;
    return native;
}

void *zgui_native_menu_add_menu(void *handle, const char *label, unsigned long len) {
    NativeMenu *native = handle;
    if (!native) return NULL;
    NSString *text = [[NSString alloc] initWithBytes:label length:len encoding:NSUTF8StringEncoding];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:text];
    [item setSubmenu:menu];
    [native->main_menu addItem:item];
    return menu;
}

int zgui_native_menu_add_item(void *handle, void *menu_handle, const char *label, unsigned long len, unsigned long long action_id) {
    NativeMenu *native = handle;
    NSMenu *menu = menu_handle;
    if (!native || !menu) return 0;
    NSString *text = [[NSString alloc] initWithBytes:label length:len encoding:NSUTF8StringEncoding];
    ZGuiMenuAction *action = [[ZGuiMenuAction alloc] init];
    action->owner = native;
    action->action_id = action_id;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text action:@selector(activate:) keyEquivalent:@""];
    [item setTarget:action];
    [item setRepresentedObject:action];
    [menu addItem:item];
    return 1;
}

void zgui_native_menu_poll(void *handle) { (void)handle; }
int zgui_native_menu_content_width(void *handle) { (void)handle; return 0; }
void zgui_native_menu_destroy(void *handle) { free(handle); }
