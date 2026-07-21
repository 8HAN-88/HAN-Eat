{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // Never register Flutter's offline SW — it causes Safari/PWA reload loops
  // and mid-deploy white screens. HTML auth + /fresh recover stuck shells.
  config: {
    // Keep Flutter's own renderer auto-selection (best Safari/iPhone compatibility),
    // but avoid dependency on external gstatic CDN for CanvasKit assets.
    useLocalCanvasKit: true,
    canvasKitBaseUrl: "canvaskit/",
  },
});
