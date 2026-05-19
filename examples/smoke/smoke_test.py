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


if __name__ == "__main__":
    unittest.main()
