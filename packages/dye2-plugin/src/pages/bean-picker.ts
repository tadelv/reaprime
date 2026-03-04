import { pageShell } from "./layout";
import { beanPickerComponent } from "../components/bean-picker";

export function renderBeanPickerPage(request: HttpRequest): HttpResponse {
  const content = `<dye2-bean-picker></dye2-bean-picker>`;
  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Select Bean", content, [beanPickerComponent]),
  };
}
