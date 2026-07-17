{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    // Prefer local CanvasKit assets instead of gstatic CDN.
    // This improves startup reliability on restrictive networks/devices.
    renderer: "canvaskit",
    useLocalCanvasKit: true,
    canvasKitVariant: "full",
  },
});
