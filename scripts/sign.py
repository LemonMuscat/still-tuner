"""Sign with a persistent private identity; restore the user's keychain search list."""
import pathlib
import shlex
import subprocess
import sys

folder = pathlib.Path.home() / 'Library/Application Support/StillTuner/Signing'
keychain = str(folder / 'still-tuner.keychain-db')
if not (folder / 'identity-sha1').is_file():
    sys.exit('Run scripts/setup-signing.sh once before building.')
identity = (folder / 'identity-sha1').read_text().strip()
password = (folder / 'keychain-password').read_text().strip()
subprocess.run(['security', 'unlock-keychain', '-p', password, keychain], check=True)
original = shlex.split(subprocess.check_output(['security', 'list-keychains', '-d', 'user'], text=True))
try:
    if keychain not in original:
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *original, keychain], check=True)
    requirement = '=designated => identifier "kr.blue.still-tuner" and certificate leaf = H"' + identity + '"'
    subprocess.run(['codesign', '--force', '--timestamp=none', '--keychain', keychain,
                    '--sign', identity, '--requirements', requirement, sys.argv[1]], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', sys.argv[1]], check=True)
finally:
    if keychain not in original:
        subprocess.run(['security', 'list-keychains', '-d', 'user', '-s', *original], check=True)
