"""Multi-platform smoke: imports a native-wheel package whose
underlying repo was picked by the selector's `select()` against
the host's @platforms constraints. If the selector mis-routed,
markupsafe's C extension would fail to import here."""

import unittest


class MultiplatformTest(unittest.TestCase):
    def test_native_wheel_via_select(self):
        from markupsafe import escape, Markup
        self.assertEqual(escape("<x>"), Markup("&lt;x&gt;"))

    def test_pure_wheel_passthrough(self):
        import idna
        self.assertEqual(idna.encode("example.com").decode(), "example.com")

    def test_pure_sdist_in_multiplatform(self):
        # `six` 1.4.1 is sdist-only — exercises the v0.6 codepath
        # where the extension installs the sdist on the host with
        # `forbid_native_extensions=True` and reuses a single repo
        # across every target platform.
        import six
        self.assertTrue(six.PY3)


if __name__ == "__main__":
    unittest.main()
