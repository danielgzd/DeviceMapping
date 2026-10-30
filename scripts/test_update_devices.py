import unittest
from update_devices import generate

class SyncTests(unittest.TestCase):
    def test_incremental_and_no_change(self):
        old = {'version': 2, 'devices': [{'identifier': 'pad', 'name': 'iPad'}]}
        new = generate([{'identifier': 'phone', 'name': 'iPhone'}], old)
        self.assertEqual(new['version'], 3)
        self.assertEqual(len(new['devices']), 2)
        self.assertEqual(generate(new['devices'], new), new)
    def test_duplicate_rejected(self):
        with self.assertRaises(ValueError):
            generate([{'identifier': 'x', 'name': 'X'}] * 2, None)
    def test_empty_rejected(self):
        with self.assertRaises(ValueError):
            generate([], None)

class CategoryTests(unittest.TestCase):
    def test_categories(self):
        from update_devices import category
        for identifier, expected in [('iPhone19,4', 'iphone'), ('iPad19,1', 'ipad'), ('MacBookPro18,1', 'mac'), ('iMac21,1', 'mac'), ('Watch7,1', 'watch'), ('AudioAccessory6,1', 'homepod'), ('RealityDevice14,1', 'vision'), ('arm64', 'simulator'), ('Unknown1,1', 'other')]:
            self.assertEqual(category(identifier), expected)
