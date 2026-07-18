{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: {
    // Keep Flutter's own renderer auto-selection (best Safari/iPhone compatibility),
    // but avoid dependency on external gstatic CDN for CanvasKit assets.
    useLocalCanvasKit: true,
    canvasKitBaseUrl: "canvaskit/",
  },
});
