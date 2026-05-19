"""Smoke test: import packages materialized via rules_uv's pip_parse."""

import unittest


class SmokeTest(unittest.TestCase):
    def test_idna_resolves(self):
        import idna
        # idna's primary API is `encode` / `decode`; a well-formed
        # round-trip is the cheapest end-to-end signal that the
        # wheel landed on disk and Python can import from it.
        self.assertEqual(idna.encode("example.com").decode(), "example.com")

    def test_certifi_resolves(self):
        import certifi
        # certifi ships a single function: a path to the CA bundle.
        path = certifi.where()
        self.assertTrue(path.endswith(".pem"))

    def test_markupsafe_native_wheel_resolves(self):
        # markupsafe is a C-extension package. Exercising it confirms
        # wheel_selection.bzl picked the right native wheel for the
        # host (cp312-cp312-<host-platform>) and Bazel unpacked it
        # into an importable tree.
        from markupsafe import escape, Markup
        self.assertEqual(escape("<x>"), Markup("&lt;x&gt;"))

    def test_iniconfig_sdist_install_resolves(self):
        # iniconfig is wired into uv.lock without a `wheels = [...]`
        # entry, so wheel_selection falls through to sdist install
        # (uv pip install --target=.). This confirms the sdist path
        # produces an importable tree end-to-end.
        import iniconfig
        self.assertTrue(hasattr(iniconfig, "IniConfig"))


if __name__ == "__main__":
    unittest.main()
