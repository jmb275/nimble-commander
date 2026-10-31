# /// script
# dependencies = []
# ///
import hashlib, importlib.util, json, os, platform, plistlib, subprocess, sys, tempfile
from pathlib import Path
from unittest.mock import patch
sys.dont_write_bytecode = True
source=Path(__file__).with_name('install_personal.py')
spec=importlib.util.spec_from_file_location('personal_installer',source)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

def make_package(package, commit):
    source_app=package/'source'/f'{m.APP_NAME}.app'
    (source_app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
    (source_app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':m.BUNDLE_ID,'NCSourceCommit':commit}))
    (source_app/'Contents/MacOS'/m.APP_NAME).write_text('fixture executable')
    archive=package/'fixture.zip'
    subprocess.run(['/usr/bin/ditto','-c','-k','--keepParent',str(source_app),str(archive)],check=True)
    (package/'manifest.json').write_text(json.dumps({'archive':archive.name,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'source_commit':commit,'architectures':[platform.machine()],'version':'fixture'}))

with tempfile.TemporaryDirectory(prefix='nc_personal_installer_',dir='/private/tmp') as temporary:
    root=Path(temporary); package=root/'package'; package.mkdir(); user_root=root/'user'
    prefs=user_root/'Dropbox/6_computing/dotfiles/nimblecommander/Config.json'; prefs.parent.mkdir(parents=True)
    prefs.write_text(json.dumps({'general':{'theme':'Classic'},'filePanel':{'general':{'openExternalRequestsInNewTab':True}}}))
    canonical=prefs.read_bytes()
    app=user_root/'Applications'/f'{m.APP_NAME}.app'
    support=user_root/'Library/Application Support'/m.APP_NAME
    config=support/'Config/Config.json'; config.parent.mkdir(parents=True)
    config.write_text('original personal config')
    values={'-g':'info.filesmanager.Files',m.ALFRED:m.TEST_ID}
    legacy_receipt=root/'legacy_test_before'; legacy_receipt.write_text(m.ABSENT); m.LEGACY_TEST_RECEIPT=legacy_receipt
    history=[]; fail_alfred_write=[False]; fail_signature=[False]
    def read(domain): return values[domain]
    def write(domain,value):
        history.append(('write',domain,value))
        if domain==m.ALFRED and value==m.BUNDLE_ID and fail_alfred_write[0]:
            fail_alfred_write[0]=False
            raise RuntimeError('simulated preference-write failure')
        values[domain]=value
    def command(*args,check=True):
        history.append(tuple(map(str,args)))
        if str(args[0])=='/usr/bin/codesign' and fail_signature[0]:
            raise subprocess.CalledProcessError(1,args,stderr='invalid fixture signature')
        if str(args[0])=='/usr/bin/ditto':
            return subprocess.run(list(map(str,args)),capture_output=True,text=True,check=check)
        if str(args[0])=='/usr/bin/pgrep': return subprocess.CompletedProcess(args,1,'','')
        return subprocess.CompletedProcess(args,0,'','')
    with patch.object(m,'read_default',read),patch.object(m,'write_default',write),patch.object(m,'command',command),patch.object(m,'restart_alfred',lambda:history.append(('restart',))):
        make_package(package,'1'*40)
        m.install(package,user_root,check_only=True)
        assert not app.exists() and not history
        m.install(package,user_root)
        assert config.is_symlink() and config.resolve()==prefs.resolve()
        assert prefs.read_bytes()==canonical
        assert all(value==m.BUNDLE_ID for value in values.values())
        first_history=len(history); m.install(package,user_root); assert len(history)==first_history
        before=json.loads((support/'Installer/before_personal.json').read_text())
        assert before=={'global':'info.filesmanager.Files','alfred':m.ABSENT}
        make_package(package,'2'*40); fail_signature[0]=True
        try: m.install(package,user_root)
        except subprocess.CalledProcessError as error: assert 'signature' in error.stderr
        else: raise AssertionError('accepted invalid signature')
        assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['NCSourceCommit']=='1'*40
        assert not list((support/'Installer').glob('app_before_*.zip'))
        assert config.is_symlink() and all(value==m.BUNDLE_ID for value in values.values())
        fail_signature[0]=False; m.install(package,user_root)
        assert len(list((support/'Installer').glob('app_before_*.zip')))==1
        assert json.loads((support/'Installer/before_personal.json').read_text())==before
        assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['NCSourceCommit']=='2'*40
        make_package(package,'3'*40); fail_alfred_write[0]=True
        try: m.install(package,user_root)
        except RuntimeError as error: assert 'simulated' in str(error)
        else: raise AssertionError('expected rollback')
        assert all(value==m.BUNDLE_ID for value in values.values())
        assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['NCSourceCommit']=='2'*40
        assert config.is_symlink() and prefs.read_bytes()==canonical
        values['-g']='later.user.choice'; m.restore(user_root)
        assert values['-g']=='later.user.choice' and values[m.ALFRED]==m.ABSENT
        assert app.exists() and config.is_symlink()
        manifest=json.loads((package/'manifest.json').read_text()); manifest['sha256']='0'*64; (package/'manifest.json').write_text(json.dumps(manifest))
        try: m.install(package,user_root)
        except RuntimeError as error: assert 'checksum' in str(error)
        else: raise AssertionError('accepted corrupt archive')
    print('PASS: package validation, saved-config linking, unchanged canonical prefs, first install, no-op repeat, signature rejection before replacement, update backup, partial-failure rollback, and guarded restore. No real apps or defaults changed.')
