"""Build relocatable skill directories from canonical, explicitly owned resources."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil

from model import Distribution, safe_path


def members(path):
    for item in sorted(Path(path).rglob('*'), key=lambda p: p.as_posix().encode()):
        if '__pycache__' in item.parts or item.suffix == '.pyc':
            continue
        if item.is_symlink():
            raise ValueError('package source contains a symlink: ' + str(item))
        if item.is_file():
            yield item


def tree_digest(path):
    path = Path(path)
    digest = hashlib.sha256()
    for item in members(path):
        digest.update((hashlib.sha256(item.read_bytes()).hexdigest() + '  ' +
                       str(item.relative_to(path)).replace('\\', '/') + '\n').encode())
    return 'sha256:' + digest.hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def copy_payload(source, destination, *, guidance=False):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    for member in members(source):
        relative = member.relative_to(source)
        if relative == Path('SKILL.md') and guidance:
            relative = Path('GUIDANCE.md')
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(member, target)


def rewrite_root_scripts(destination, resources):
    own_name = destination.name
    targets = {name: destination / 'resources/runtime' / name for name in resources}
    # The destination may be a staging directory named differently from the ID.
    frontmatter = (destination / 'SKILL.md').read_text()
    match = re.search(r'^name:\s*(.+)$', frontmatter, re.M)
    own_name = match.group(1)
    targets[own_name] = destination
    for item in members(destination):
        relative = item.relative_to(destination)
        if item.suffix not in {'.sh', '.ps1', '.py', '.md', '.cjs'}:
            continue
        text = item.read_text()
        original = text
        for name, target in targets.items():
            local = os.path.relpath(target, item.parent).replace('\\', '/')
            text = text.replace('../../' + name + '/', local + '/')
            if item.suffix == '.sh':
                # Historical helpers locate other scripts via a global skills root.
                # Bind these executable paths locally even when that global root exists.
                pattern = r'\$(?:\{(?:SKILLS_DIR|skills_dir|root)\}|(?:SKILLS_DIR|skills_dir|root))/' + re.escape(name) + '/'
                path = '$(CDPATH= cd -- "$(dirname "$0")/' + local + '" && pwd -P)/'
                text = re.sub(pattern, lambda _: path, text)
        if text != original:
            item.write_text(text)


def render_skill(source_body, name, resources):
    if not source_body.startswith('---\n'):
        raise ValueError('missing skill frontmatter: ' + name)
    _, frontmatter, body = source_body.split('---', 2)
    title = re.search(r'^name:\s*(.+)$', frontmatter, re.M)
    description = re.search(r'^description:\s*(.+)$', frontmatter, re.M)
    if not title or title.group(1) != name or not description:
        raise ValueError('skill identity/description mismatch: ' + name)
    lines = ['---', 'name: ' + name, 'description: ' + description.group(1), '---', '',
        'This directory is an independent skill. Resolve paths relative to this SKILL.md,',
        'and run commands on the selected target through its existing authorized Transport.',
        'Other Kai skills named below are optional specialists; this directory contains',
        'the executable resources required by its own workflow.', '']
    if re.search(r'^invocation:\s*manual\s*$', frontmatter, re.M):
        lines[3:3] = ['metadata:', '  opencode/autoinvoke: "false"']
    if resources:
        lines += ['## Local supporting resources', '']
        for resource in resources:
            lines.append('- `' + resource + '`: [local instructions](resources/runtime/' +
                         resource + '/GUIDANCE.md); executable helpers under that resource’s `scripts/`.')
        if 'kai-tool-bootstrap' in resources:
            lines += ['', 'Prepare tools locally with `bash resources/runtime/kai-tool-bootstrap/scripts/tool.sh plan TOOL`',
                      'and its explicit `ensure TOOL` operation when needed. Before Bash exists on Windows,',
                      'use `resources/runtime/kai-tool-bootstrap/scripts/bootstrap-bash.ps1 -Action Plan`',
                      'through native PowerShell, then the authorized Ensure operation.']
        if 'kai-dev-environment' in resources:
            lines += ['', 'SDK helpers are local at `resources/runtime/kai-dev-environment/scripts/runtime.sh`.']
        lines += ['', '## Business workflow', '']
    body = re.sub(r'Before calling Bash scripts, prepare an existing compatible Bash with kai-tool-bootstrap\.[^\n]*\n',
        'Use the local bootstrap resource above for missing Bash/tools.\n' if 'kai-tool-bootstrap' in resources else
        'Prepare compatible Bash; the native Windows first entry is in this skill’s scripts/bootstrap-bash.ps1.\n', body)
    # Existing iStoreOS instructions must also work outside KaiPlus's directory layout.
    body = re.sub(r'SKILLS_DIR="\$\{KAIPLUS_SKILLS_DIR:-\$\{KAIPLUS_HOME:\?KAIPLUS_HOME is required\}/config/skills\}"',
                  'SKILLS_DIR="<absolute-parent-of-this-skill-directory>"', body)
    return '\n'.join(lines) + body.lstrip(), frontmatter.strip() + '\n'


def build_package(distribution, name, destination):
    if name not in distribution.packages:
        raise ValueError('unknown independent skill: ' + name)
    destination = Path(destination)
    if destination.exists() or destination.is_symlink():
        raise ValueError('package destination must be fresh')
    source = safe_path(distribution.root, distribution.resources[name])
    resources = distribution.runtime_closure(name)
    # Mutual historical resources must be able to refer back to this package too.
    if any(name in distribution.config.get('runtimeResources', {}).get(r, []) for r in resources):
        resources = sorted(set(resources + [name]))
    copy_payload(source, destination)
    sources = [{'id': name, 'canonicalPath': distribution.resources[name], 'sourceDigest': tree_digest(source)}]
    for resource in resources:
        resource_source = safe_path(distribution.root, distribution.resources[resource])
        copy_payload(resource_source, destination / 'resources/runtime' / resource, guidance=True)
        sources.append({'id': resource, 'canonicalPath': distribution.resources[resource],
                        'sourceDigest': tree_digest(resource_source)})
    rewrite_root_scripts(destination, resources)
    rendered, frontmatter = render_skill((source / 'SKILL.md').read_text(), name, resources)
    (destination / 'SKILL.md').write_text(rendered)
    if re.search(r'^invocation:\s*manual\s*$', frontmatter, re.M) and not (destination / 'agents/openai.yaml').exists():
        (destination / 'agents').mkdir(exist_ok=True)
        (destination / 'agents/openai.yaml').write_text('policy:\n  allow_implicit_invocation: false\n')
    write_json(destination / 'resources/source-metadata.json',
               {'schemaVersion': 1, 'originalFrontmatter': frontmatter,
                'transform': 'business-self-contained-v1', 'sources': sources})
    # Metadata has no self-referential digest. The external lock hashes the entire directory.
    metadata = dict(distribution.packages[name], resourceSources=sources)
    write_json(destination / 'skill-package.json', metadata)
    metadata['treeDigest'] = tree_digest(destination)
    return metadata
