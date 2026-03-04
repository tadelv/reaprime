import { pageShell } from "./layout";

export function renderGrindersPage(request: HttpRequest): HttpResponse {
  const content = `<p class="text-muted">Grinder management coming soon.</p>`;

  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Grinders", content),
  };
}
