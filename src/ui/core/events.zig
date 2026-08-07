const platform_events = @import("../platform/events.zig");
const types = @import("types.zig");

pub const PlatformEvent = platform_events.PlatformEvent;
pub const MouseButton = platform_events.MouseButton;
pub const Key = platform_events.Key;
pub const CursorKind = platform_events.CursorKind;

pub const PointerActivation = struct {
    button: MouseButton,
    position: types.Vec2,
};

pub const KeyboardActivation = struct {
    key: Key,
};

pub const ActivationSource = union(enum) {
    pointer: PointerActivation,
    keyboard: KeyboardActivation,
};

/// A widget-level activation. Pointer activation is emitted after the primary
/// button is pressed and released over the same interactive node. The source
/// union also leaves room for keyboard activation without changing handlers.
pub const Activation = struct {
    target: types.NodeId,
    source: ActivationSource,
};

/// Semantic events produced by zGUI after platform input has been routed.
/// Additional widget events can be added without changing callback storage.
pub const Event = union(enum) {
    activate: Activation,

    pub fn target(self: Event) types.NodeId {
        return switch (self) {
            .activate => |activation| activation.target,
        };
    }
};

/// Type-erased, non-owning callback. The bound context must remain at a stable
/// address until the handler is replaced, cleared, or its node is destroyed.
pub const EventHandler = struct {
    context: ?*anyopaque,
    function: *const fn (?*anyopaque, Event) void,

    pub fn bind(context: anytype, comptime function: fn (@TypeOf(context), Event) void) EventHandler {
        const Context = @TypeOf(context);
        const context_info = @typeInfo(Context);
        if (context_info != .pointer or context_info.pointer.size != .one) {
            @compileError("event handler context must be a single-item pointer");
        }

        return .{
            .context = @ptrCast(@constCast(context)),
            .function = struct {
                fn invoke(raw_context: ?*anyopaque, event: Event) void {
                    const typed_context: Context = @ptrCast(@alignCast(raw_context.?));
                    function(typed_context, event);
                }
            }.invoke,
        };
    }

    pub fn stateless(comptime function: fn (Event) void) EventHandler {
        return .{
            .context = null,
            .function = struct {
                fn invoke(_: ?*anyopaque, event: Event) void {
                    function(event);
                }
            }.invoke,
        };
    }

    pub fn call(self: EventHandler, event: Event) void {
        self.function(self.context, event);
    }
};
