/**
 * Tagged template literal for HTML strings.
 * Provides a visual marker for syntax highlighting in editors.
 * Does NOT escape interpolated values — use escapeHtml() for user data.
 */
export function html(
  strings: TemplateStringsArray,
  ...values: unknown[]
): string {
  return strings.reduce((result, str, i) => {
    const value = i < values.length ? String(values[i]) : "";
    return result + str + value;
  }, "");
}

/** Escape HTML special characters in user-provided strings */
export function escapeHtml(unsafe: string): string {
  return unsafe
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#039;");
}
