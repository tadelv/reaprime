import { pageShell } from "./layout";
import { grinderPickerComponent } from "../components/grinder-picker";

export function renderGrinderPickerPage(
  request: HttpRequest,
): HttpResponse {
  const content = `<dye2-grinder-picker></dye2-grinder-picker>`;
  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Select Grinder", content, [grinderPickerComponent]),
  };
}
