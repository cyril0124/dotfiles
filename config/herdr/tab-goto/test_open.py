"""Regression tests for content-based popup sizing."""

import unittest

from open import content_size


def tabs(count: int, groups: int) -> list[dict[str, str]]:
    return [
        {"workspace_id": f"w{i % groups}", "workspace": "workspace", "tab": "tab", "status": ""}
        for i in range(count)
    ]


class PopupSizeTests(unittest.TestCase):
    def test_fits_tabs_and_workspace_headers_on_tall_terminal(self):
        self.assertEqual(content_size(tabs(40, 8), 200, 65)[1], 54)

    def test_uses_available_height_before_scrolling(self):
        rows = tabs(55, 2)
        self.assertEqual(content_size(rows, 200, 65)[1], 63)
        self.assertEqual(content_size(rows, 200, 30)[1], 30)

    def test_stays_inside_small_terminal(self):
        width, height = content_size(tabs(4, 2), 30, 8)
        self.assertLessEqual(width, 30)
        self.assertEqual(height, 8)


if __name__ == "__main__":
    unittest.main()
