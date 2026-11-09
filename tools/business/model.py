"""Read-only distribution model. Bundles select packages, never install programs."""
import copy
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
ID = re.compile(r'^[a-z0-9][a-z0-9-]{0,63}$')
VERSION = re.compile(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')


def safe_path(root, relative):
    root = Path(root).absolute()
    path = root / relative
    if not relative or Path(relative).is_absolute() or '..' in Path(relative).parts:
        raise ValueError('unsafe relative path: ' + str(relative))
    if path.resolve() != path.absolute() or root.resolve() not in path.resolve().parents:
        raise ValueError('source path contains an alias or escapes root: ' + str(relative))
    if not path.exists():
        raise ValueError('missing source: ' + str(relative))
    return path


def identity(value):
    if not isinstance(value, str) or not ID.fullmatch(value):
        raise ValueError('invalid package identity: ' + repr(value))
    return value


def validate_locked_members(members):
    seen = {}
    for member in members:
        key = identity(member['id'])
        if not VERSION.fullmatch(member['version']):
            raise ValueError('invalid locked version')
        if not re.fullmatch(r'sha256:[0-9a-f]{64}', member['treeDigest']):
            raise ValueError('invalid locked digest')
        if key in seen and seen[key] != member:
            raise ValueError('conflicting locked package: ' + key)
        seen[key] = member
    return [seen[key] for key in sorted(seen)]


class Distribution:
    def __init__(self, root=ROOT, declaration=None):
        self.root = Path(root).resolve()
        self.config = copy.deepcopy(declaration) if declaration is not None else self.read('components/business.json')
        if self.config.get('schemaVersion') != 1 or not VERSION.fullmatch(self.config.get('releaseVersion', '')):
            raise ValueError('unsupported business declaration or invalid release version')
        self.composition = self.read('components/composition.json')
        self.legacy = self.read('catalog.json')
        private_resources = {name for preset in self.composition['presets'].values()
                             for name in preset['compatibilityResources']}
        self.packages, self.resources = {}, {}
        for component, relative in self.composition['componentRoots'].items():
            source = safe_path(self.root, relative)
            base = source / 'skills'
            for skill in sorted(base.iterdir()) if base.exists() else []:
                if not (skill / 'SKILL.md').is_file():
                    continue
                name = identity(skill.name)
                path = str(skill.relative_to(self.root))
                safe_path(self.root, path)
                if name in self.resources:
                    raise ValueError('duplicate canonical skill: ' + name)
                self.resources[name] = path
                if name in private_resources:
                    continue
                platforms = sorted({p['platform'] for p in self.legacy['presets']
                    if component in p['generatedFrom'] and
                    (not component.startswith('transport.') or any(
                        t['component'] == component and name in t['skills']
                        for t in self.composition['presets'][p['id']]['transports']))})
                body = (skill / 'SKILL.md').read_text()
                if component in ('common', 'linux'):
                    if not name.startswith('kai-'):
                        raise ValueError('shared skills require the kai- prefix: ' + name)
                    frontmatter = body.split('---', 2)[1] if body.startswith('---') else ''
                    if re.search(r'^aliases\s*:', frontmatter, re.M):
                        raise ValueError('shared skills must not publish aliases: ' + name)
                description = re.search(r'^description:\s*(.+)$', body, re.M)
                self.packages[name] = {
                    'id': name, 'version': self.config['releaseVersion'],
                    'path': 'skills/' + name, 'canonicalPath': path,
                    'description': description.group(1) if description else name,
                    'platforms': platforms, 'kind': 'transport' if component.startswith('transport.') else 'business',
                    'component': component,
                    'architectures': {p: self.config['architectureSupport'][p] for p in platforms},
                    'programRequirements': self.config.get('programRequirements', {}).get(name, ['target programs documented in SKILL.md']),
                }
        self.bundles = copy.deepcopy(self.config['bundles'])
        for name, value in self.bundles.items():
            identity(name)
            if not value.get('skills') and not value.get('bundles'):
                raise ValueError('empty bundle: ' + name)
            self.expand(name)
        for name, dependencies in self.config.get('runtimeResources', {}).items():
            if name not in self.resources or any(d not in self.resources for d in dependencies):
                raise ValueError('missing runtime resource in ' + name)

    def read(self, relative):
        return json.loads(safe_path(self.root, relative).read_text())

    def expand(self, bundle, chain=()):
        identity(bundle)
        if bundle in chain:
            raise ValueError('cyclic bundle reference: ' + ' -> '.join((*chain, bundle)))
        if bundle not in self.bundles:
            raise ValueError('unknown bundle: ' + bundle)
        value = self.bundles[bundle]
        names = set(value.get('skills', []))
        if not names <= self.packages.keys():
            raise ValueError('missing bundle members: ' + ', '.join(sorted(names - self.packages.keys())))
        for other in value.get('bundles', []):
            names.update(self.expand(other, (*chain, bundle)))
        return sorted(names)

    def runtime_closure(self, name):
        # Resource graphs may contain mutual references; each source is embedded once.
        pending, seen = [name], set()
        while pending:
            item = pending.pop()
            if item in seen:
                continue
            seen.add(item)
            pending.extend(self.config.get('runtimeResources', {}).get(item, []))
        return sorted(seen - {name})

    def select(self, *, skill=None, bundle=None, platform=None, all_skills=False,
               mode=None, architecture=None, own_transport=False):
        if sum([skill is not None, bundle is not None, bool(all_skills)]) != 1:
            raise ValueError('choose exactly one skill, business bundle, or platform --all')
        if platform and platform not in self.config['architectureSupport']:
            raise ValueError('unsupported platform: ' + platform)
        if mode not in (None, 'on-device', 'remote-control'):
            raise ValueError('unsupported execution mode')
        if architecture and (not platform or architecture not in self.config['architectureSupport'][platform]):
            raise ValueError('unsupported or unspecified platform architecture')
        if all_skills and (not platform or not mode):
            raise ValueError('platform --all requires a target platform and execution mode')
        if mode == 'remote-control' and not platform:
            raise ValueError('remote-control requires the target platform')
        if skill is not None:
            identity(skill)
            if skill not in self.packages:
                raise ValueError('unknown skill: ' + skill)
            names, selection = [skill], 'skill:' + skill
        elif bundle is not None:
            names, selection = self.expand(bundle), 'bundle:' + bundle
        else:
            names = sorted(k for k, p in self.packages.items()
                           if p['kind'] == 'business' and platform in p['platforms'])
            selection = 'system:' + platform + ':' + mode
        if platform:
            incompatible = [n for n in names if platform not in self.packages[n]['platforms']]
            if incompatible:
                raise ValueError('incompatible packages for ' + platform + ': ' + ', '.join(incompatible))
        if mode == 'remote-control' and not own_transport:
            entry = next(p for p in self.legacy['presets']
                         if p['platform'] == platform and p['mode'] == mode)
            for transport in self.composition['presets'][entry['id']]['transports']:
                names.extend(transport['skills'])
        names = sorted(set(names))
        return {'schemaVersion': 1, 'selection': selection, 'platform': platform,
                'mode': mode, 'architecture': architecture,
                'packages': [copy.deepcopy(self.packages[n]) for n in names],
                'programOperations': [], 'serviceOperations': False}

    def catalog(self):
        return {'schemaVersion': 1, 'version': self.config['releaseVersion'],
                'skills': list(self.packages.values()), 'bundles': self.bundles,
                'legacyCatalog': 'catalog.json', 'defaultPolicy': {'installAll': False}}
