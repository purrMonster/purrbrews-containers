"""Digest coverage and public registry reference validation."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Images(unittest.TestCase):
    def test_collector_and_hub_keep_their_image_variants(self):
        collector = (ROOT / "stacks/_shared/scrutiny-collector.yml").read_text()
        hub = (ROOT / "stacks/cellar/scrutiny/docker-compose.yml").read_text()
        self.assertRegex(collector, r"image: ghcr.io/analogj/scrutiny:v[\d.]+-collector@sha256:")
        self.assertRegex(hub, r"image: ghcr.io/analogj/scrutiny:v[\d.]+-omnibus@sha256:")

    def test_all_active_images_match_reviewed_lock(self):
        self.assertGreater(load("check_images", "check-images.py").check(ROOT), 40)

    def test_reference_parser(self):
        images = load("images", "images.py")
        self.assertEqual(images.split_reference("postgres:18.6"),
                         ("registry-1.docker.io", "library/postgres", "18.6"))
        self.assertEqual(images.split_reference("ghcr.io/example/app:v1@sha256:abc"),
                         ("ghcr.io", "example/app", "v1"))
        for invalid in ("missing-tag", "ghcr.io/../private:v1", "app:tag?bad"):
            with self.assertRaises(ValueError):
                images.split_reference(invalid)
