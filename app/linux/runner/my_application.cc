#include "my_application.h"
#include <initializer_list>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* security_channel;
  GtkWidget* privacy_cover;
  GtkWidget* security_view;
  GDBusConnection* session_bus;
  GDBusConnection* system_bus;
  gboolean security_ready;
  gboolean privacy_pending;
  guint session_subscriptions[3];
  guint sleep_subscription;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// The native overlay covers the previous surface before Dart handles suspend.
static void redact_for_system_lock(MyApplication* self) {
  self->privacy_pending = TRUE;
  if (self->privacy_cover) gtk_widget_show(self->privacy_cover);
  if (self->security_view) gtk_widget_set_sensitive(self->security_view, FALSE);
  if (self->security_ready && self->security_channel) {
    fl_method_channel_invoke_method(self->security_channel, "suspend", nullptr, nullptr, nullptr, nullptr);
  }
}
static void security_signal(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                            const gchar*, GVariant* parameters, gpointer data) {
  if (!g_variant_is_of_type(parameters, G_VARIANT_TYPE("(b)"))) return;
  gboolean active = FALSE;
  g_variant_get(parameters, "(b)", &active);
  if (active) redact_for_system_lock(MY_APPLICATION(data));
}
static void security_method(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  MyApplication* self = MY_APPLICATION(data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "ready") == 0) {
    self->security_ready = TRUE;
    if (self->privacy_pending) redact_for_system_lock(self);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_strcmp0(method, "privacyReady") == 0) {
    self->privacy_pending = FALSE;
    if (self->privacy_cover) gtk_widget_hide(self->privacy_cover);
    if (self->security_view) gtk_widget_set_sensitive(self->security_view, TRUE);
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else { fl_method_call_respond_not_implemented(call, nullptr); }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "OpenWard");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "OpenWard");
  }

  gtk_window_set_default_size(window, 1280, 720);
  // As on macOS: under 760×480 the window holds too little to work in.
  GdkGeometry hints = {};
  hints.min_width = 760;
  hints.min_height = 480;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->security_view = GTK_WIDGET(view);
  g_object_add_weak_pointer(G_OBJECT(view), reinterpret_cast<gpointer*>(&self->security_view));
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  GtkWidget* overlay = gtk_overlay_new();
  gtk_container_add(GTK_CONTAINER(overlay), GTK_WIDGET(view));
  self->privacy_cover = gtk_event_box_new();
  // CSS avoids deprecated GTK color APIs under the runner's -Werror policy.
  GtkCssProvider* css = gtk_css_provider_new();
  gtk_css_provider_load_from_data(css, "* { background-color: black; }", -1, nullptr);
  gtk_style_context_add_provider(gtk_widget_get_style_context(self->privacy_cover), GTK_STYLE_PROVIDER(css), GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
  g_object_unref(css);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), self->privacy_cover);
  gtk_widget_set_no_show_all(self->privacy_cover, TRUE);
  gtk_widget_show(overlay);
  gtk_container_add(GTK_CONTAINER(window), overlay);
  g_object_add_weak_pointer(G_OBJECT(self->privacy_cover), reinterpret_cast<gpointer*>(&self->privacy_cover));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->security_channel = fl_method_channel_new(fl_engine_get_binary_messenger(fl_view_get_engine(view)), "openward/security", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->security_channel, security_method, self, nullptr);
  self->session_bus = g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, nullptr);
  if (self->session_bus) {
    size_t subscription_index = 0;
    for (const char* service : {"org.freedesktop.ScreenSaver", "org.gnome.ScreenSaver", "org.cinnamon.ScreenSaver"}) {
      self->session_subscriptions[subscription_index++] = g_dbus_connection_signal_subscribe(self->session_bus, service, service, "ActiveChanged", nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE, security_signal, self, nullptr);
    }
  }
  self->system_bus = g_bus_get_sync(G_BUS_TYPE_SYSTEM, nullptr, nullptr);
  if (self->system_bus) self->sleep_subscription = g_dbus_connection_signal_subscribe(self->system_bus, "org.freedesktop.login1", "org.freedesktop.login1.Manager", "PrepareForSleep", "/org/freedesktop/login1", nullptr, G_DBUS_SIGNAL_FLAGS_NONE, security_signal, self, nullptr);

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  if (self->security_channel) fl_method_channel_set_method_call_handler(self->security_channel, nullptr, nullptr, nullptr);
  g_clear_object(&self->security_channel);
  if (self->session_bus) for (guint id : self->session_subscriptions) { if (id) g_dbus_connection_signal_unsubscribe(self->session_bus, id); }
  if (self->system_bus && self->sleep_subscription) g_dbus_connection_signal_unsubscribe(self->system_bus, self->sleep_subscription);
  g_clear_object(&self->session_bus);
  g_clear_object(&self->system_bus);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
