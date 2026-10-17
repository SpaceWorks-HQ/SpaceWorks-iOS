import importlib.util
from pathlib import Path
import unittest
SPEC = importlib.util.spec_from_file_location('brand_links', Path(__file__).resolve().parents[1] / 'brand_links.py')
LINKS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LINKS)
class BrandLinksTest(unittest.TestCase):
    def test_unconfigured_links_remain_nullable_without_invented_destinations(self):
        self.assertEqual(LINKS.validated_links({}), {'support_url': None, 'privacy_url': None})
    def test_legal_paths_queries_fragments_and_ports_are_preserved(self):
        for value in ('https://help.example.org/support/contact?topic=account&lang=en#email',
                      'https://privacy.example.org:8443/legal/a%20b?return=$account#retention',
                      'https://[2001:db8::1]:443/privacy', 'https://localhost/privacy'):
            with self.subTest(value=value):
                self.assertEqual(LINKS.optional_https_url(value, 'support_url'), value)

    def test_scheme_and_idna_host_are_normalized_for_native_external_links(self):
        self.assertEqual(LINKS.optional_https_url('HTTPS://B\u00dcCHER.example:0443/p%20a?q=$owner#legal', 'support_url'),
                         'https://xn--bcher-kva.example:0443/p%20a?q=$owner#legal')
        self.assertEqual(LINKS.optional_https_url('HTTPS://[2001:DB8::1]:443/policy', 'privacy_url'),
                         'https://[2001:db8::1]:443/policy')
        self.assertEqual(LINKS.optional_https_url('HTTPS://EXAMPLE.ORG/legal', 'support_url'),
                         'https://example.org/legal')

    def test_malformed_escapes_and_raw_java_uri_illegal_characters_are_rejected(self):
        for suffix in ('%ZZ', '%2', '%', 'a{b}', 'a}b', 'a"b', 'a<b', 'a>b', 'a|b',
                       'a^b', 'a`b', 'a[b]', '?q={bad}', '#bad#fragment'):
            with self.subTest(suffix=suffix), self.assertRaises(ValueError):
                LINKS.optional_https_url('https://example.org/' + suffix, 'privacy_url')
        self.assertEqual(LINKS.optional_https_url('https://example.org/a%7Bb%7D?q=%22ok%22#part%25', 'privacy_url'),
                         'https://example.org/a%7Bb%7D?q=%22ok%22#part%25')

    def test_insecure_relative_missing_host_credentials_and_malformed_authority_are_rejected(self):
        for value in ('', 'http://example.org', '//example.org/a', '/legal', 'https:example.org',
                      'https:///legal', 'https://', 'javascript:alert(1)',
                      'https://user:secret@example.org/legal', 'https://@example.org',
                      'https://example.org@attacker.example', 'https://example.org:bad',
                      'https://example.org:65536', 'https://example.org:',
                      'https://bad%2f.example/legal', 'https://.example.org', 'https://[invalid]/'):
            with self.subTest(value=value), self.assertRaises(ValueError):
                LINKS.optional_https_url(value, 'privacy_url')

    def test_controls_whitespace_backslashes_and_nonstring_values_are_rejected(self):
        for value in (' https://example.org', 'https://example.org ', 'https://example.org/a b',
                      'https://example.org\n', 'https://example.org/\tpolicy',
                      'https://example.org/\x00policy', 'https://example.org/\x7f',
                      'https://example.org/\u200bpolicy', 'https://example.org/\u00a0policy',
                      'https://example.org\\@attacker.example', True, False, 42, [], {}):
            with self.subTest(value=value), self.assertRaises(ValueError):
                LINKS.optional_https_url(value, 'support_url')

    def test_error_does_not_echo_private_value(self):
        with self.assertRaises(ValueError) as result:
            LINKS.optional_https_url('https://user:super-secret@example.org/private', 'support_url')
        self.assertIn('support_url', str(result.exception))
        self.assertNotIn('super-secret', str(result.exception))
        self.assertNotIn('example.org', str(result.exception))


if __name__ == "__main__": unittest.main()
