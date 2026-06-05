import 'package:flutter_test/flutter_test.dart';
import 'package:reaprime/src/webui_support/webui_service.dart';

void main() {
  const token = 'abc.123';
  const script = '<script>window.__REA_PROXY_TOKEN__="abc.123";</script>';

  test('injects before </head> when present', () {
    final out = injectProxyTokenScript(
      '<html><head><title>x</title></head><body>hi</body></html>',
      token,
    );
    expect(out, contains('$script</head>'));
    expect(out.indexOf(script), lessThan(out.indexOf('<body>')));
  });

  test('injects before </body> when there is no head', () {
    final out = injectProxyTokenScript('<body>hi</body>', token);
    expect(out, '<body>hi$script</body>');
  });

  test('prepends when neither head nor body is present', () {
    final out = injectProxyTokenScript('just text', token);
    expect(out, '${script}just text');
  });

  test('returns html unchanged when token is null or empty', () {
    const html = '<html><head></head></html>';
    expect(injectProxyTokenScript(html, null), html);
    expect(injectProxyTokenScript(html, ''), html);
  });

  test('json-encodes the token (escapes quotes)', () {
    final out = injectProxyTokenScript('<head></head>', 'a"b');
    expect(out, contains(r'window.__REA_PROXY_TOKEN__="a\"b";'));
  });
}
