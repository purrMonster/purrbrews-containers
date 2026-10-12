"""Comments say why an image is pinned, not which version: the image line says that.

Dependabot moves only the `image:` line, so a version repeated in a comment is
wrong after the next bump (2026-10-13: Home Assistant's and Open WebUI's were).
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHANNELS = {'main', 'latest', 'release', 'stable'}
IMAGE = re.compile(r'^\s*(?:image|x-image):\s*(?:&\w+\s+)?([^\s@]+):([^\s@]+)', re.M)


class ImageComments(unittest.TestCase):
    def test_comments_never_repeat_a_pinned_tag(self):
        for compose in sorted((ROOT / 'stacks').glob('*/*/docker-compose.yml')):
            text = compose.read_text(encoding='utf-8')
            comments = '\n'.join(line for line in text.splitlines() if line.lstrip().startswith('#'))
            for name, tag in IMAGE.findall(text):
                if tag in CHANNELS:  # a channel name doesn't change with a bump
                    continue
                short = name.rsplit('/', 1)[-1]
                with self.subTest(file=str(compose.relative_to(ROOT)), image=f'{name}:{tag}'):
                    self.assertNotIn(f'{short}:{tag}', comments,
                                     'name the image in the comment, not its tag')


if __name__ == '__main__':
    unittest.main()
