import { pageShell } from "./layout";
import { grinderListComponent } from "../components/grinder-list";

export function renderGrindersPage(request: HttpRequest): HttpResponse {
  const content = `<dye2-grinder-list></dye2-grinder-list>`;

  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Grinders", content, [grinderListComponent]),
  };
}
