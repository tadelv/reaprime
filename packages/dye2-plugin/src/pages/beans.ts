import { pageShell } from "./layout";
import { beanListComponent } from "../components/bean-list";

export function renderBeansPage(request: HttpRequest): HttpResponse {
  const content = `<dye2-bean-list></dye2-bean-list>`;

  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Beans", content, [beanListComponent]),
  };
}
