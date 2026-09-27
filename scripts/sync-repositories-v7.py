#!/usr/bin/env python3
import csv
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
final_path = pathlib.Path(sys.argv[2])
archive_path = pathlib.Path(sys.argv[3])
base_url = sys.argv[4].rstrip('/')
codename = sys.argv[5]
required = [item for item in sys.argv[6].split(',') if item]

with manifest_path.open(encoding='utf-8', newline='') as handle:
    rows = list(csv.DictReader(handle, delimiter='\t'))
by_id = {row['id']: row for row in rows}

# "__all__" mirrors the default behaviour of add-ailinux-repo.sh: include every
# published mirror entry that targets this codename (plus entries targeting "*"
# or no specific codename). This keeps the ISO build-time and installed runtime
# repository sets aligned with the full AILinux mirror.
if required == ['__all__']:
    required = [
        row['id']
        for row in rows
        if (row.get('target_codename') or '').strip() in ('', '*', codename)
    ]

missing = [repo_id for repo_id in required if repo_id not in by_id]
if missing:
    raise SystemExit('Required mirror entries missing: ' + ', '.join(missing))

keyring = '/usr/share/keyrings/ailinux-archive-keyring.gpg'
final_lines = [
    '# AILinux mirror repositories',
    f'# Generated from {base_url}/mirror-repos.tsv',
    f'# Target codename: {codename}',
]
archive_lines = [
    '# Build-time AILinux mirror repositories',
    f'# Generated from {base_url}/mirror-repos.tsv',
]

for repo_id in required:
    row = by_id[repo_id]
    target = (row.get('target_codename') or '').strip()
    if target not in ('', '*', codename):
        raise SystemExit(f'Mirror {repo_id} targets {target}, expected {codename}')
    label = row['label'].strip()
    uri = f"{base_url}/{row['path'].strip('/')}"
    suite = row['suite'].strip()
    components = row['components'].strip()
    arches = row['architectures'].strip()
    final_lines.extend(['', f'# {label} [{repo_id}]'])
    archive_lines.extend(['', f'# {label} [{repo_id}]'])
    if suite == '/':
        final_lines.append(f'deb [arch={arches} signed-by={keyring}] {uri} /')
        archive_lines.append(f'deb [arch={arches}] {uri} /')
    else:
        suffix = '' if components == '-' else ' ' + components
        final_lines.append(f'deb [arch={arches} signed-by={keyring}] {uri} {suite}{suffix}')
        archive_lines.append(f'deb [arch={arches}] {uri} {suite}{suffix}')

final_path.parent.mkdir(parents=True, exist_ok=True)
archive_path.parent.mkdir(parents=True, exist_ok=True)
final_path.write_text('\n'.join(final_lines) + '\n', encoding='utf-8')
archive_path.write_text('\n'.join(archive_lines) + '\n', encoding='utf-8')
print('Selected mirror entries: ' + ', '.join(required))
