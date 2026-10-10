import importlib.util
import json
from pathlib import Path
import stat
import tempfile
import unittest
import zipfile

HELPER = Path(__file__).resolve().parents[1] / 'os/files/usr/lib/marwanos/browser_extensions.py'
spec = importlib.util.spec_from_file_location('browser_extensions', HELPER)
extensions = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extensions)


class BrowserExtensionsTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.base = Path(self.temporary.name)
        self.store = extensions.Store(self.base / 'profile')

    def tearDown(self):
        self.temporary.cleanup()

    def package(self, extras=None, prefix='', manifest=None):
        path = self.base / 'extension.zip'
        manifest = manifest or {'manifest_version': 3, 'name': 'Reader', 'version': '1.2',
                                'permissions': ['storage'], 'host_permissions': ['https://example.com/*'],
                                'content_scripts': [{'matches': ['https://example.org/*'], 'js': ['reader.js']}]}
        with zipfile.ZipFile(path, 'w') as archive:
            archive.writestr(prefix + 'manifest.json', json.dumps(manifest))
            archive.writestr(prefix + 'reader.js', "document.title = 'extension works';")
            for name, content in (extras or {}).items():
                archive.writestr(name, content)
        return path

    def install(self, package):
        reviewed = extensions.inspect_archive(package)
        return self.store.install(package, reviewed['digest'])

    def test_review_reports_api_and_website_access_without_installing(self):
        review = extensions.inspect_archive(self.package())
        self.assertEqual(review['permissions'], ['https://example.com/*', 'https://example.org/*', 'storage'])
        self.assertEqual(self.store.entries, [])
        self.assertFalse(self.store.index.exists())

    def test_install_persists_files_and_enabled_state(self):
        entry = self.install(self.package())
        self.assertTrue((self.store.root / entry['uid'] / 'manifest.json').is_file())
        self.assertTrue(extensions.Store(self.store.root).entries[0]['enabled'])
        self.assertEqual(list(self.store.root.glob('.install-*')), [])

    def test_review_includes_optional_permissions(self):
        review = extensions.inspect_archive(self.package(manifest={
            'manifest_version': 3, 'name': 'Reader', 'version': '1',
            'optional_permissions': ['bookmarks'], 'optional_host_permissions': ['https://example.net/*']}))
        self.assertEqual(review['permissions'], ['Optional: bookmarks', 'Optional: https://example.net/*'])

    def test_invalid_versions_and_translated_names_are_rejected(self):
        for version in ('0', '0.0', '65536', '01.2', '1.2.3.4.5'):
            with self.subTest(version=version), self.assertRaisesRegex(ValueError, 'version'):
                extensions.inspect_archive(self.package(manifest={
                    'manifest_version': 3, 'name': 'Reader', 'version': version}))
        with self.assertRaisesRegex(ValueError, 'translated name'):
            extensions.inspect_archive(self.package(
                manifest={'manifest_version': 3, 'name': '__MSG_name__', 'default_locale': 'en', 'version': '1'},
                extras={'_locales/en/messages.json': '["malformed"]'}))

    def test_enclosing_publisher_folder_is_stripped(self):
        entry = self.install(self.package(prefix='reader-release/'))
        self.assertTrue((self.store.root / entry['uid'] / 'reader.js').is_file())

    def test_disabled_and_removed_state_survives_reopening(self):
        entry = self.install(self.package())
        self.store.change('disable', entry['uid'])
        self.assertFalse(extensions.Store(self.store.root).entries[0]['enabled'])
        self.store.change('enable', entry['uid'])
        self.assertTrue(extensions.Store(self.store.root).entries[0]['enabled'])
        self.store.change('remove', entry['uid'])
        self.assertEqual(extensions.Store(self.store.root).entries, [])
        self.assertTrue((self.store.root / entry['uid']).exists(), 'keep files while Chromium may still be using them')
        self.store.prune()
        self.assertFalse((self.store.root / entry['uid']).exists())

    def test_changed_zip_requires_another_review(self):
        package = self.package()
        digest = extensions.inspect_archive(package)['digest']
        self.package(extras={'changed.js': 'new code'})
        with self.assertRaisesRegex(ValueError, 'changed after review'):
            self.store.install(package, digest)
        self.assertEqual(self.store.entries, [])

    def test_duplicate_package_does_not_overwrite_or_duplicate_state(self):
        package = self.package()
        entry = self.install(package)
        with self.assertRaisesRegex(ValueError, 'already installed'):
            self.install(package)
        self.assertEqual(self.store.entries, [entry])

    def test_path_traversal_absolute_and_windows_paths_are_rejected(self):
        for name in ('../escaped', '/absolute', 'C:/escaped'):
            with self.subTest(name=name), self.assertRaisesRegex(ValueError, 'unsafe file path'):
                extensions.inspect_archive(self.package(extras={name: 'unsafe'}))
        self.assertFalse((self.base / 'escaped').exists())
        package = self.package(extras={'folder/escaped': 'unsafe'})
        package.write_bytes(package.read_bytes().replace(b'folder/escaped', b'folder\\escaped'))
        with self.assertRaisesRegex(ValueError, 'unsafe file path'):
            extensions.inspect_archive(package)

    def test_symlinks_are_rejected(self):
        package = self.package()
        with zipfile.ZipFile(package, 'a') as archive:
            info = zipfile.ZipInfo('linked.js')
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, '/etc/passwd')
        with self.assertRaisesRegex(ValueError, 'links'):
            extensions.inspect_archive(package)

    def test_duplicate_paths_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            extensions.inspect_archive(self.package(extras={'READER.JS': 'duplicate'}))

    def test_expansion_limit_is_checked_before_extraction(self):
        package = self.package(extras={'large.txt': 'x' * 100})
        old = extensions.MAX_FILE
        try:
            extensions.MAX_FILE = 50
            with self.assertRaisesRegex(ValueError, 'too large'):
                extensions.inspect_archive(package)
        finally:
            extensions.MAX_FILE = old

    def test_manifest_v2_and_missing_manifest_are_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Manifest V3'):
            extensions.inspect_archive(self.package(manifest={'manifest_version': 2, 'name': 'Old', 'version': '1'}))
        package = self.base / 'empty.zip'
        with zipfile.ZipFile(package, 'w') as archive:
            archive.writestr('readme.txt', 'not an extension')
        with self.assertRaisesRegex(ValueError, 'manifest.json'):
            extensions.inspect_archive(package)

    def test_pruning_preserves_disabled_packages_and_unrelated_directories(self):
        entry = self.install(self.package())
        self.store.change('disable', entry['uid'])
        unrelated = self.store.root / 'notes'
        unrelated.mkdir()
        self.store.prune()
        self.assertTrue(unrelated.exists())
        self.assertTrue((self.store.root / entry['uid']).exists())


if __name__ == '__main__':
    unittest.main()
