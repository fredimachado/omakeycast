#!/usr/bin/env python3
import importlib.util
import os
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SPEC = importlib.util.spec_from_file_location("listen_keys", os.path.join(ROOT, "listen-keys.py"))
lk = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(lk)


class ComboTrackerTests(unittest.TestCase):
    def setUp(self):
        self.tracker = lk.ComboTracker()

    def press(self, code):
        return self.tracker.handle(code, lk.KEY_PRESS)

    def release(self, code):
        return self.tracker.handle(code, lk.KEY_RELEASE)

    def test_plain_letter_is_ignored(self):
        self.assertIsNone(self.press(30))  # A

    def test_ctrl_a(self):
        self.assertIsNone(self.press(lk.KEY_LEFTCTRL))
        self.assertEqual(self.press(30), "Ctrl + A")

    def test_super_ctrl_return(self):
        self.assertIsNone(self.press(lk.KEY_LEFTMETA))
        self.assertIsNone(self.press(lk.KEY_LEFTCTRL))
        self.assertEqual(self.press(28), "Super + Ctrl + Return")

    def test_shift_alone_with_letter_is_ignored(self):
        self.assertIsNone(self.press(lk.KEY_LEFTSHIFT))
        self.assertIsNone(self.press(30))

    def test_ctrl_shift_a_includes_shift(self):
        self.assertIsNone(self.press(lk.KEY_LEFTCTRL))
        self.assertIsNone(self.press(lk.KEY_LEFTSHIFT))
        self.assertEqual(self.press(30), "Ctrl + Shift + A")

    def test_alt_tab(self):
        self.assertIsNone(self.press(lk.KEY_LEFTALT))
        self.assertEqual(self.press(15), "Alt + Tab")

    def test_right_modifiers(self):
        self.assertIsNone(self.press(lk.KEY_RIGHTMETA))
        self.assertIsNone(self.press(lk.KEY_RIGHTALT))
        self.assertEqual(self.press(1), "Super + Alt + Escape")

    def test_repeat_does_not_reemit(self):
        self.press(lk.KEY_LEFTCTRL)
        self.assertEqual(self.press(30), "Ctrl + A")
        self.assertIsNone(self.tracker.handle(30, lk.KEY_REPEAT))

    def test_mouse_buttons_ignored(self):
        self.press(lk.KEY_LEFTCTRL)
        self.assertIsNone(self.press(0x110))

    def test_release_clears_modifier(self):
        self.press(lk.KEY_LEFTCTRL)
        self.release(lk.KEY_LEFTCTRL)
        self.assertIsNone(self.press(30))

    def test_skip_virtual_keyboards(self):
        self.assertTrue(lk.should_skip("hl-virtual-keyboard-1"))
        self.assertTrue(lk.should_skip("Power Button"))
        self.assertTrue(lk.should_skip("Consumer Control"))
        self.assertFalse(lk.should_skip("AT Translated Set 2 keyboard"))


if __name__ == "__main__":
    unittest.main()
