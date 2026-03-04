/// <reference path="./host.d.ts" />

export default function createPlugin(host: PluginHost): PluginInstance {
  function log(msg: string) {
    host.log(`[dye2] ${msg}`);
  }

  return {
    id: "dye2.reaplugin",
    version: "0.1.0",

    onLoad(_settings: Record<string, unknown>) {
      log("DYE2 plugin loaded");
    },

    onUnload() {
      log("DYE2 plugin unloaded");
    },

    onEvent(_event: PluginEvent) {
      // MVP: no event processing
    },

    __httpRequestHandler(request: HttpRequest): HttpResponse {
      log(`HTTP ${request.method} ${request.endpoint}`);

      switch (request.endpoint) {
        case "beans":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Beans</title></head>
<body>
  <h1>Streamline/DYE2 - Beans Management</h1>
  <p>Plugin scaffold working. Components coming soon.</p>
</body>
</html>`,
          };

        case "grinders":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Grinders</title></head>
<body>
  <h1>Streamline/DYE2 - Grinders Management</h1>
  <p>Plugin scaffold working. Components coming soon.</p>
</body>
</html>`,
          };

        case "bean-picker":
        case "grinder-picker":
          return {
            requestId: request.requestId,
            status: 200,
            headers: { "Content-Type": "text/html; charset=utf-8" },
            body: `<!DOCTYPE html>
<html>
<head><title>DYE2 - Picker</title></head>
<body>
  <h1>Streamline/DYE2 - ${request.endpoint}</h1>
  <p>Picker scaffold working.</p>
</body>
</html>`,
          };

        default:
          return {
            requestId: request.requestId,
            status: 404,
            headers: { "Content-Type": "text/plain" },
            body: "Not found",
          };
      }
    },
  };
}
