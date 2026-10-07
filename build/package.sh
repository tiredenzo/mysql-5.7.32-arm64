#!/usr/bin/env bash
set -Eeuo pipefail

# Package the original release manifests without service/database maintainer
# scripts. The historical recipe also built a separate Debug tree; this image
# intentionally ships the release tree, so mysqld-debug and plugin/debug are out.
test "$(dpkg --print-architecture)" = arm64
# CMake regenerates the source tree's Debian templates. Restore the verified
# published packaging before using its install manifests and support files.
tar -xJf /inputs/mysql-community_5.7.32-1debian10.debian.tar.xz -C /src/mysql

python3 - <<'PY'
import glob
import os
from pathlib import Path
import shlex
import shutil
import subprocess

source = Path('/src/mysql')
installed = Path('/install')
package_roots = Path('/build/package-roots')
output = Path('/packages')
provenance = Path('/build/provenance')
version = '5.7.32-1debian10+arm64.1'
packages = (
    'mysql-common', 'libmysqlclient20', 'mysql-community-client',
    'mysql-client', 'mysql-community-server', 'mysql-server',
)

# Oracle's override_dh_auto_install adds these after CMake installation.
for relative, original, mode in (
    ('usr/share/mysql/mysql-helpers', 'debian/extra/mysql-helpers', 0o644),
    ('usr/share/mysql/mysql-systemd-start', 'debian/extra/mysql-systemd-start', 0o755),
    ('usr/share/man/man1/mysql_embedded.1', 'debian/extra/mysql_embedded.1', 0o644),
):
    target = installed / relative
    if not target.exists():
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source / original, target)
        target.chmod(mode)

runtime_libraries = (
    'libaio1, libnuma1, libatomic1, libncurses6, libtinfo6, libmecab2, '
    'libldap-2.4-2, libsasl2-2, libstdc++6, zlib1g'
)
dependencies = {
    'mysql-common': '',
    'libmysqlclient20': f'mysql-common (= {version}), {runtime_libraries}',
    'mysql-community-client': f'mysql-common (= {version}), {runtime_libraries}, perl',
    'mysql-client': f'mysql-community-client (= {version})',
    'mysql-community-server': (
        f'mysql-common (= {version}), mysql-client (= {version}), '
        f'{runtime_libraries}, perl, psmisc'
    ),
    'mysql-server': f'mysql-community-server (= {version})',
}
descriptions = {
    'mysql-common': 'Oracle MySQL 5.7.32 common configuration and support files',
    'libmysqlclient20': 'Oracle MySQL 5.7.32 shared client library',
    'mysql-community-client': 'Oracle MySQL 5.7.32 native clients and administration tools',
    'mysql-client': 'Oracle MySQL 5.7.32 client metapackage',
    'mysql-community-server': 'Oracle MySQL 5.7.32 native server and release plugins',
    'mysql-server': 'Oracle MySQL 5.7.32 server metapackage',
}

def copy_entry(item, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if item.is_dir() and not item.is_symlink():
        shutil.copytree(item, target, symlinks=True)
    else:
        shutil.copy2(item, target, follow_symlinks=False)

package_roots.mkdir(parents=True, exist_ok=True)
output.mkdir(parents=True, exist_ok=True)
provenance.mkdir(parents=True, exist_ok=True)
inventory = []
omissions = []

for package in packages:
    root = package_roots / package
    root.mkdir()
    manifest = source / 'debian' / (package + '.install')
    for number, line in enumerate(manifest.read_text().splitlines(), start=1):
        words = shlex.split(line, comments=True)
        if not words:
            continue
        if len(words) not in (1, 2):
            raise SystemExit(f'{manifest}:{number}: unsupported install syntax: {line}')
        pattern = words[0].lstrip('/')
        if pattern == 'usr/sbin/mysqld-debug' or pattern.startswith('usr/lib/mysql/plugin/debug/'):
            omissions.append(f'{package}: {pattern} (separate Debug build omitted)')
            continue
        if pattern == 'usr/share/man/man1/mysqlman.1':
            omissions.append(f'{package}: {pattern} (excluded by original override_dh_install)')
            continue
        origin = source if pattern.startswith('debian/') else installed
        matches = sorted(Path(p) for p in glob.glob(str(origin / pattern)))
        if not matches:
            raise SystemExit(f'{manifest}:{number}: missing required installed file: {pattern}')
        for item in matches:
            if len(words) == 2:
                target = root / words[1].lstrip('/') / item.name
            else:
                target = root / item.relative_to(origin)
            copy_entry(item, target)

    doc = root / 'usr/share/doc' / package
    doc.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / 'debian/copyright', doc / 'copyright')
    debian = root / 'DEBIAN'
    debian.mkdir()
    control = (
        f'Package: {package}\nVersion: {version}\nArchitecture: arm64\n'
        'Maintainer: Local ARM64 image build <local-build@example.invalid>\n'
        'Section: database\nPriority: optional\n'
        f'Description: {descriptions[package]}\n'
        ' Built from Oracle MySQL 5.7.32 sources for the standalone ARM64 image.\n'
    )
    if dependencies[package]:
        control += f'Depends: {dependencies[package]}\n'
    if package == 'libmysqlclient20':
        control += 'Multi-Arch: same\n'
    elif package == 'mysql-common':
        control += 'Multi-Arch: foreign\n'
    (debian / 'control').write_text(control)
    conffiles = sorted(
        '/' + str(path.relative_to(root))
        for path in (root / 'etc').rglob('*')
        if path.is_file() or path.is_symlink()
    ) if (root / 'etc').exists() else []
    if conffiles:
        (debian / 'conffiles').write_text('\n'.join(conffiles) + '\n')
    if package == 'mysql-common':
        # All six packages are unpacked together before dpkg configures them;
        # mysql.cnf is supplied by the original server install manifest.
        postinst = debian / 'postinst'
        postinst.write_text(
            '#!/bin/sh\nset -e\n'
            'if [ "$1" = configure ]; then\n'
            '    update-alternatives --install /etc/mysql/my.cnf my.cnf /etc/mysql/mysql.cnf 200\n'
            'fi\n'
        )
        postinst.chmod(0o755)
    if package == 'libmysqlclient20':
        (debian / 'triggers').write_text('activate-noawait ldconfig\n')

    inventory.extend(
        f'{package}: /{path.relative_to(root)}'
        for path in sorted(root.rglob('*'))
        if 'DEBIAN' not in path.relative_to(root).parts
        and (path.is_file() or path.is_symlink())
    )
    destination = output / f'{package}_{version}_arm64.deb'
    subprocess.run(['dpkg-deb', '--root-owner-group', '--build', str(root), str(destination)], check=True)

(provenance / 'package-files.txt').write_text('\n'.join(inventory) + '\n')
(provenance / 'package-omissions.txt').write_text('\n'.join(omissions) + '\n')
(provenance / 'package-notes.txt').write_text(
    'Six local Debian packages use Oracle install manifests, version ' + version + '.\n'
    'Separate Debug binaries/plugins are omitted; all required release-manifest files are present.\n'
    'mysqlman.1 is excluded by the original packaging rule.\n'
    'Original database/service maintainer scripts are not executed.\n'
    'Only the standard my.cnf alternative and ldconfig trigger are registered.\n'
    'Runtime reference configuration is applied by the final image layer.\n'
    'Release binaries retain compiler debug information; no debug server is included.\n'
)
PY
