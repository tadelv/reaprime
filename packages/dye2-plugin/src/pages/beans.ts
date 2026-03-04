import { pageShell } from "./layout";
import { beanListComponent } from "../components/bean-list";
import { beanFormComponent } from "../components/bean-form";

/** Page-level orchestration: show/hide form, refresh list on save */
const beanPageOrchestration = `
document.addEventListener('create-bean', () => {
  const form = document.querySelector('dye2-bean-form');
  form.removeAttribute('bean-id');
  form.classList.remove('hidden');
  form.connectedCallback();
});
document.addEventListener('select-bean', (e) => {
  const form = document.querySelector('dye2-bean-form');
  form.setAttribute('bean-id', e.detail.id);
  form.classList.remove('hidden');
  form.connectedCallback();
});
document.addEventListener('bean-saved', () => {
  document.querySelector('dye2-bean-form').classList.add('hidden');
  document.querySelector('dye2-bean-list').fetchBeans();
});
document.addEventListener('bean-cancelled', () => {
  document.querySelector('dye2-bean-form').classList.add('hidden');
});
`;

export function renderBeansPage(request: HttpRequest): HttpResponse {
  const content = `
    <dye2-bean-list></dye2-bean-list>
    <dye2-bean-form class="hidden"></dye2-bean-form>
  `;

  return {
    requestId: request.requestId,
    status: 200,
    headers: { "Content-Type": "text/html; charset=utf-8" },
    body: pageShell("Beans", content, [
      beanListComponent,
      beanFormComponent,
      beanPageOrchestration,
    ]),
  };
}
