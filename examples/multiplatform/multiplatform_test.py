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


if __name__ == "__main__":
    unittest.main()
