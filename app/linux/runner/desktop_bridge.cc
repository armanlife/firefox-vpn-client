#include "desktop_bridge.h"

#include <dlfcn.h>
#include <glib/gstdio.h>

#include <cstring>
#include <initializer_list>
#include <set>
#include <string>

namespace {

// The AppIndicator functions this file uses, from libayatana-appindicator3
// (or the older libappindicator3) when the system has it.
typedef GObject AppIndicator;
typedef AppIndicator* (*IndicatorNew)(const gchar* id, const gchar* icon,
                                      int category);
typedef void (*IndicatorSetStatus)(AppIndicator* indicator, int status);
typedef void (*IndicatorSetIcon)(AppIndicator* indicator, const gchar* icon,
                                 const gchar* description);
typedef void (*IndicatorSetTitle)(AppIndicator* indicator, const gchar* title);
typedef void (*IndicatorSetMenu)(AppIndicator* indicator, GtkMenu* menu);
typedef void (*IndicatorSetTarget)(AppIndicator* indicator, GtkWidget* item);
typedef void (*IndicatorSetThemePath)(AppIndicator* indicator,
                                      const gchar* path);

constexpr int kCategoryApplicationStatus = 0;
constexpr int kStatusPassive = 0;
constexpr int kStatusActive = 1;

struct Indicator {
  IndicatorNew create = nullptr;
  IndicatorSetStatus set_status = nullptr;
  IndicatorSetIcon set_icon = nullptr;
  IndicatorSetTitle set_title = nullptr;
  IndicatorSetMenu set_menu = nullptr;
  IndicatorSetTarget set_target = nullptr;
  IndicatorSetThemePath set_theme_path = nullptr;

  bool Load() {
    for (const char* name : {"libayatana-appindicator3.so.1",
                             "libappindicator3.so.1"}) {
      void* lib = dlopen(name, RTLD_NOW | RTLD_GLOBAL);
      if (lib == nullptr) {
        continue;
      }
      create = reinterpret_cast<IndicatorNew>(dlsym(lib, "app_indicator_new"));
      set_status = reinterpret_cast<IndicatorSetStatus>(
          dlsym(lib, "app_indicator_set_status"));
      set_icon = reinterpret_cast<IndicatorSetIcon>(
          dlsym(lib, "app_indicator_set_icon_full"));
      set_title = reinterpret_cast<IndicatorSetTitle>(
          dlsym(lib, "app_indicator_set_title"));
      set_menu = reinterpret_cast<IndicatorSetMenu>(
          dlsym(lib, "app_indicator_set_menu"));
      set_target = reinterpret_cast<IndicatorSetTarget>(
          dlsym(lib, "app_indicator_set_secondary_activate_target"));
      set_theme_path = reinterpret_cast<IndicatorSetThemePath>(
          dlsym(lib, "app_indicator_set_icon_theme_path"));
      if (create && set_status && set_icon && set_menu) {
        return true;
      }
    }
    return false;
  }
};

constexpr const char* kAutostartFile = "arman-vpn.desktop";

}  // namespace

struct _DesktopBridge {
  GtkWindow* window;
  FlMethodChannel* channel;
  Indicator api;
  AppIndicator* indicator;
  std::string icon_path;
  // icon_dir holds the tray icons under names of their own (tray_icon).
  std::string icon_dir;
  std::set<std::string> icons_copied;
  std::string app_icon;
  bool allow_close;
  GDBusConnection* bus;
  guint notification;
};

static const gchar* string_arg(FlValue* args, const char* key) {
  FlValue* v = args ? fl_value_lookup_string(args, key) : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : "";
}

static bool bool_arg(FlValue* args, const char* key, bool fallback) {
  FlValue* v = args ? fl_value_lookup_string(args, key) : nullptr;
  return v && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL ? fl_value_get_bool(v)
                                                         : fallback;
}

static void invoke(DesktopBridge* self, const char* method, FlValue* value) {
  fl_method_channel_invoke_method(self->channel, method, value, nullptr,
                                  nullptr, nullptr);
}

static void show_window(DesktopBridge* self) {
  gtk_widget_show(GTK_WIDGET(self->window));
  gtk_window_present(self->window);
}

static void on_menu_item(GtkMenuItem* item, gpointer user_data) {
  auto* self = static_cast<DesktopBridge*>(user_data);
  int id = GPOINTER_TO_INT(g_object_get_data(G_OBJECT(item), "id"));
  if (id > 0) {
    invoke(self, "trayMenu", fl_value_new_int(id));
  }
}

// The menu from the Dart side's items. The first item (Open) also answers
// the indicator's middle click, its only click besides the menu.
static GtkWidget* build_menu(DesktopBridge* self, FlValue* items, bool rtl,
                             GtkWidget** first) {
  GtkWidget* menu = gtk_menu_new();
  gtk_widget_set_direction(menu, rtl ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_LTR);
  size_t n = fl_value_get_length(items);
  for (size_t i = 0; i < n; i++) {
    FlValue* item = fl_value_get_list_value(items, i);
    if (fl_value_get_type(item) != FL_VALUE_TYPE_MAP) {
      continue;
    }
    if (bool_arg(item, "separator", false)) {
      gtk_menu_shell_append(GTK_MENU_SHELL(menu),
                            gtk_separator_menu_item_new());
      continue;
    }
    const gchar* label = string_arg(item, "label");
    FlValue* children = fl_value_lookup_string(item, "children");
    GtkWidget* entry;
    if (bool_arg(item, "checked", false)) {
      entry = gtk_check_menu_item_new_with_label(label);
      gtk_check_menu_item_set_active(GTK_CHECK_MENU_ITEM(entry), TRUE);
    } else {
      entry = gtk_menu_item_new_with_label(label);
    }
    gtk_widget_set_direction(entry, rtl ? GTK_TEXT_DIR_RTL : GTK_TEXT_DIR_LTR);
    gtk_widget_set_sensitive(entry, bool_arg(item, "enabled", true));
    if (children && fl_value_get_type(children) == FL_VALUE_TYPE_LIST) {
      gtk_menu_item_set_submenu(GTK_MENU_ITEM(entry),
                                build_menu(self, children, rtl, nullptr));
    } else {
      FlValue* id = fl_value_lookup_string(item, "id");
      int value = id && fl_value_get_type(id) == FL_VALUE_TYPE_INT
                      ? static_cast<int>(fl_value_get_int(id))
                      : 0;
      g_object_set_data(G_OBJECT(entry), "id", GINT_TO_POINTER(value));
      // Connected after set_active, so building the menu sends nothing.
      g_signal_connect(entry, "activate", G_CALLBACK(on_menu_item), self);
      if (first && *first == nullptr) {
        *first = entry;
      }
    }
    gtk_menu_shell_append(GTK_MENU_SHELL(menu), entry);
  }
  gtk_widget_show_all(menu);
  return menu;
}

// tray_icon is the icon at path as the tray takes it: a name in an icon
// folder of the app's own, where each icon is copied once, rather than the
// file path, which some trays (StatusNotifierItem hosts) do not resolve.
// The name is armanvpntray_<file>: no theme has it, and it has no dash,
// since KDE looks a name up in the system's theme first and drops its
// dashed parts until one matches ("arman-vpn-off" showed Firefox's own
// icon). Without the library's icon folder call, the path goes.
static std::string tray_icon(DesktopBridge* self, const gchar* path) {
  if (self->api.set_theme_path == nullptr || path[0] == '\0') {
    return path;
  }
  if (self->icon_dir.empty()) {
    g_autofree gchar* dir = g_build_filename(g_get_user_runtime_dir(),
                                             "arman-vpn-tray", nullptr);
    g_mkdir_with_parents(dir, 0700);
    self->icon_dir = dir;
    self->api.set_theme_path(self->indicator, dir);
  }
  g_autofree gchar* base = g_path_get_basename(path);
  gchar* dot = strrchr(base, '.');
  if (dot) {
    *dot = '\0';
  }
  std::string name = std::string("armanvpntray_") + base;
  if (self->icons_copied.insert(name).second) {
    g_autofree gchar* data = nullptr;
    gsize length = 0;
    std::string file = name + ".png";
    g_autofree gchar* copy =
        g_build_filename(self->icon_dir.c_str(), file.c_str(), nullptr);
    if (!g_file_get_contents(path, &data, &length, nullptr) ||
        !g_file_set_contents(copy, data, length, nullptr)) {
      self->icons_copied.erase(name);
      return path;
    }
  }
  return name;
}

static void set_tray(DesktopBridge* self, FlValue* args) {
  if (self->indicator == nullptr) {
    return;
  }
  const gchar* icon = string_arg(args, "icon");
  const gchar* tooltip = string_arg(args, "tooltip");
  if (self->icon_path != icon) {
    self->icon_path = icon;
    std::string name = tray_icon(self, icon);
    self->api.set_icon(self->indicator, name.c_str(), tooltip);
  }
  if (self->api.set_title) {
    self->api.set_title(self->indicator, tooltip);
  }
  FlValue* items = fl_value_lookup_string(args, "items");
  if (items && fl_value_get_type(items) == FL_VALUE_TYPE_LIST) {
    GtkWidget* first = nullptr;
    GtkWidget* menu =
        build_menu(self, items, bool_arg(args, "rtl", false), &first);
    // The indicator keeps the menu; the old one goes with its reference.
    self->api.set_menu(self->indicator, GTK_MENU(menu));
    if (first && self->api.set_target) {
      self->api.set_target(self->indicator, first);
    }
  }
  self->api.set_status(self->indicator, kStatusActive);
}

static void on_notification_action(GDBusConnection*, const gchar*,
                                   const gchar*, const gchar*, const gchar*,
                                   GVariant* parameters, gpointer user_data) {
  auto* self = static_cast<DesktopBridge*>(user_data);
  guint32 id = 0;
  const gchar* action = nullptr;
  g_variant_get(parameters, "(u&s)", &id, &action);
  if (id == self->notification && g_strcmp0(action, "default") == 0) {
    invoke(self, "trayClicked", nullptr);
  }
}

static void on_notified(GObject* source, GAsyncResult* result,
                        gpointer user_data) {
  auto* self = static_cast<DesktopBridge*>(user_data);
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, nullptr);
  if (reply) {
    g_variant_get(reply, "(u)", &self->notification);
  }
}

// A notification through org.freedesktop.Notifications; clicking it opens
// the window, as the tray icon does.
static void notify(DesktopBridge* self, const gchar* title, const gchar* body) {
  if (self->bus == nullptr) {
    return;
  }
  GVariantBuilder actions;
  g_variant_builder_init(&actions, G_VARIANT_TYPE("as"));
  g_variant_builder_add(&actions, "s", "default");
  g_variant_builder_add(&actions, "s", "Open");
  GVariantBuilder hints;
  g_variant_builder_init(&hints, G_VARIANT_TYPE("a{sv}"));
  g_dbus_connection_call(
      self->bus, "org.freedesktop.Notifications",
      "/org/freedesktop/Notifications", "org.freedesktop.Notifications",
      "Notify",
      g_variant_new("(susssasa{sv}i)", "Arman VPN", self->notification,
                    self->app_icon.c_str(), title, body, &actions, &hints, -1),
      G_VARIANT_TYPE("(u)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, on_notified,
      self);
}

// The XDG autostart entry that starts the app at sign-in.
static void set_autostart(DesktopBridge* self, bool enabled,
                          const gchar* command) {
  g_autofree gchar* dir =
      g_build_filename(g_get_user_config_dir(), "autostart", nullptr);
  g_autofree gchar* path = g_build_filename(dir, kAutostartFile, nullptr);
  // The entry's name before 1.0.9.
  g_autofree gchar* legacy =
      g_build_filename(dir, "firefox-vpn-client.desktop", nullptr);
  g_unlink(legacy);
  if (!enabled || command[0] == '\0') {
    g_unlink(path);
    return;
  }
  g_mkdir_with_parents(dir, 0700);
  g_autofree gchar* entry = g_strdup_printf(
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=Arman VPN\n"
      "Exec=%s\n"
      "Icon=%s\n"
      "Terminal=false\n"
      "X-GNOME-Autostart-enabled=true\n",
      command, self->app_icon.c_str());
  g_file_set_contents(path, entry, -1, nullptr);
}

// The program the user picks in the system's open dialog (the desktop's
// portal where it has one), or null when the dialog is cancelled.
static FlValue* pick_program(DesktopBridge* self, const gchar* title) {
  GtkFileChooserNative* chooser = gtk_file_chooser_native_new(
      title, self->window, GTK_FILE_CHOOSER_ACTION_OPEN, nullptr, nullptr);
  FlValue* picked = nullptr;
  if (gtk_native_dialog_run(GTK_NATIVE_DIALOG(chooser)) ==
      GTK_RESPONSE_ACCEPT) {
    g_autofree gchar* path =
        gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(chooser));
    if (path) {
      picked = fl_value_new_string(path);
    }
  }
  g_object_unref(chooser);
  return picked ? picked : fl_value_new_null();
}

static void method_call_cb(FlMethodChannel*, FlMethodCall* call,
                           gpointer user_data) {
  auto* self = static_cast<DesktopBridge*>(user_data);
  const gchar* name = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (strcmp(name, "pickProgram") == 0) {
    g_autoptr(FlValue) picked = pick_program(self, string_arg(args, "title"));
    fl_method_call_respond_success(call, picked, nullptr);
    return;
  }
  if (strcmp(name, "setTray") == 0) {
    set_tray(self, args);
  } else if (strcmp(name, "notify") == 0) {
    notify(self, string_arg(args, "title"), string_arg(args, "body"));
  } else if (strcmp(name, "setAutostart") == 0) {
    set_autostart(self, bool_arg(args, "enabled", false),
                  string_arg(args, "command"));
  } else if (strcmp(name, "show") == 0) {
    show_window(self);
  } else if (strcmp(name, "hide") == 0) {
    // Without a tray icon the window could not come back: minimize it.
    if (self->indicator) {
      gtk_widget_hide(GTK_WIDGET(self->window));
    } else {
      gtk_window_iconify(self->window);
    }
  } else if (strcmp(name, "quit") == 0) {
    self->allow_close = true;
    if (self->indicator) {
      self->api.set_status(self->indicator, kStatusPassive);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    gtk_window_close(self->window);
    return;
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

static gboolean delete_event_cb(GtkWidget*, GdkEvent*, gpointer user_data) {
  auto* self = static_cast<DesktopBridge*>(user_data);
  if (self->allow_close) {
    return FALSE;
  }
  invoke(self, "closeRequested", nullptr);
  return TRUE;
}

gchar* app_icon_path() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar* dir = g_path_get_dirname(exe ? exe : ".");
  return g_build_filename(dir, "data", "app_icon.png", nullptr);
}

DesktopBridge* desktop_bridge_new(FlView* view, GtkWindow* window) {
  auto* self = new DesktopBridge();
  self->window = window;
  self->indicator = nullptr;
  self->allow_close = false;
  self->notification = 0;
  g_autofree gchar* icon = app_icon_path();
  self->app_icon = icon;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "app/desktop",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);
  if (self->api.Load()) {
    self->indicator = self->api.create(
        "arman-vpn", "network-vpn", kCategoryApplicationStatus);
  }
  self->bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (self->bus) {
    g_dbus_connection_signal_subscribe(
        self->bus, "org.freedesktop.Notifications",
        "org.freedesktop.Notifications", "ActionInvoked",
        "/org/freedesktop/Notifications", nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        on_notification_action, self, nullptr);
  }
  g_signal_connect(window, "delete-event", G_CALLBACK(delete_event_cb), self);
  return self;
}

void desktop_bridge_activate(DesktopBridge* self) {
  show_window(self);
  invoke(self, "shown", nullptr);
}
