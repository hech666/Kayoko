"""Verify lean package composition without disabling runtime safeguards."""
import io, subprocess, sys, tarfile
for path in sys.argv[1:]:
    raw = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', path])
    archive = tarfile.open(fileobj=io.BytesIO(raw))
    files = {m.name.lstrip('./'): archive.extractfile(m).read() for m in archive.getmembers() if m.isfile()}
    assert not any(n.endswith(('.m', '.h', '.py')) for n in files), 'Source/tests must not be packaged'
    binaries = {n: b for n, b in files.items() if b[:4] in (b'\xca\xfe\xba\xbe', b'\xcf\xfa\xed\xfe')}
    assert len(binaries) == 4
    for n, b in binaries.items():
        assert b'AlertUtil\0' not in b and b'StringUtil\0' not in b, (n, 'unused utility present')
        if n.endswith('/KayokoPreferences'):
            for name in ('PasteboardManager', 'PasteboardItem', 'KayokoClipboardExecutor', 'KayokoHistoryStore', 'ImageUtil'):
                assert (name+'\0').encode() not in b, (n, name)
            for name in ('KayokoRootListController', 'KayokoCreditsListController', 'LinkCell', 'SingleContactCell'):
                assert (name+'\0').encode() in b, (n, name)
        elif n.endswith(('KayokoCore.dylib', 'KayokoHelper.dylib')):
            for name in ('PasteboardManager', 'PasteboardItem', 'KayokoClipboardExecutor', 'KayokoHistoryStore', 'ImageUtil'):
                assert (name+'\0').encode() in b, (n, name)
    print('PASS: lean package contains four binaries, no unused utility classes; settings excludes clipboard services, tweaks retain safeguards:', path)
