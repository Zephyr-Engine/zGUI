#import <AppKit/AppKit.h>
#include <stdint.h>
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

static NSMenuItem *action_item(NativeMenu *native, NSString *title, NSString *key_equivalent, unsigned long long action_id) {
    ZGuiMenuAction *action = [[ZGuiMenuAction alloc] init];
    if (!action) return nil;
    action->owner = native;
    action->action_id = action_id;

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(activate:) keyEquivalent:key_equivalent];
    if (!item) {
        [action release];
        return nil;
    }
    [item setTarget:action];
    /* NSMenuItem does not retain its target. Keep the action alive for as
       long as the item belongs to the menu. */
    [item setRepresentedObject:action];
    [action release];
    return item;
}

void *zgui_native_menu_create(unsigned long long window_handle, const char *title, unsigned long title_len, void *context, NativeCallback callback) {
    (void)window_handle;
    if (!callback) return NULL;
    NativeMenu *native = calloc(1, sizeof(*native));
    if (!native) return NULL;
    native->callback = callback;
    native->context = context;
    [NSApplication sharedApplication];
    native->main_menu = [[NSMenu alloc] initWithTitle:@""];
    if (!native->main_menu) {
        free(native);
        return NULL;
    }

    NSString *application_name = [[NSString alloc] initWithBytes:title length:title_len encoding:NSUTF8StringEncoding];
    if (!application_name) {
        [native->main_menu release];
        free(native);
        return NULL;
    }

    /* AppKit reserves the first top-level menu for the application. Without
       it, the first client menu is displayed under the process name and the
       standard Command-Q shortcut disappears. */
    NSMenuItem *application_item = [[NSMenuItem alloc] initWithTitle:application_name action:nil keyEquivalent:@""];
    NSMenu *application_menu = [[NSMenu alloc] initWithTitle:application_name];
    NSString *quit_title = [[NSString alloc] initWithFormat:@"Quit %@", application_name];
    NSMenuItem *quit_item = action_item(native, quit_title, @"q", UINT64_MAX);
    if (!application_item || !application_menu || !quit_title || !quit_item) {
        [quit_item release];
        [quit_title release];
        [application_menu release];
        [application_item release];
        [application_name release];
        [native->main_menu release];
        free(native);
        return NULL;
    }
    [quit_item setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
    [application_menu addItem:quit_item];
    [application_item setSubmenu:application_menu];
    [native->main_menu addItem:application_item];

    [[NSApplication sharedApplication] setMainMenu:native->main_menu];
    [quit_item release];
    [quit_title release];
    [application_menu release];
    [application_item release];
    [application_name release];
    return native;
}

void *zgui_native_menu_add_menu(void *handle, const char *label, unsigned long len) {
    NativeMenu *native = handle;
    if (!native) return NULL;
    NSString *text = [[NSString alloc] initWithBytes:label length:len encoding:NSUTF8StringEncoding];
    if (!text) return NULL;
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:text action:nil keyEquivalent:@""];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:text];
    if (!item || !menu) {
        [menu release];
        [item release];
        [text release];
        return NULL;
    }
    [item setSubmenu:menu];
    [native->main_menu addItem:item];
    [item release];
    [text release];
    [menu release];
    return menu;
}

int zgui_native_menu_add_item(void *handle, void *menu_handle, const char *label, unsigned long len, unsigned long long action_id) {
    NativeMenu *native = handle;
    NSMenu *menu = menu_handle;
    if (!native || !menu) return 0;
    NSString *text = [[NSString alloc] initWithBytes:label length:len encoding:NSUTF8StringEncoding];
    if (!text) return 0;
    NSMenuItem *item = action_item(native, text, @"", action_id);
    [text release];
    if (!item) return 0;
    [menu addItem:item];
    [item release];
    return 1;
}

void zgui_native_menu_poll(void *handle) { (void)handle; }
int zgui_native_menu_content_width(void *handle) { (void)handle; return 0; }
void zgui_native_menu_destroy(void *handle) {
    NativeMenu *native = handle;
    if (!native) return;
    NSApplication *application = [NSApplication sharedApplication];
    if ([application mainMenu] == native->main_menu) [application setMainMenu:nil];
    [native->main_menu release];
    free(native);
}
