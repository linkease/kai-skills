#!/usr/bin/env python3
"""Compose canonical packs and third-party presets from one declaration."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT=Path(os.environ.get('LINKEASE_SKILLS_ROOT',Path(__file__).resolve().parents[1])).resolve()


def read(path):
    return json.loads(path.read_text())


def write(path,value):
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n')


def files(path):
    candidates=[path] if path.is_file() else path.rglob('*')
    for item in candidates:
        if '__pycache__' in item.parts or item.suffix=='.pyc':continue
        if item.is_symlink():raise ValueError('source symlinks require an explicit resource contract: '+str(item))
        if item.is_file():yield item


def digest(paths,base):
    members={str(p.relative_to(base)):p for root in paths for p in files(root)}
    value=hashlib.sha256()
    for name in sorted(members,key=lambda name:name.encode()):
        sha=hashlib.sha256(members[name].read_bytes()).hexdigest()
        value.update((sha+'  '+name+'\n').encode())
    return 'sha256:'+value.hexdigest()


def copy(source,destination,resource=False):
    list(files(source))  # reject symlinks before following any source
    shutil.copytree(source,destination,ignore=shutil.ignore_patterns('__pycache__','*.pyc',*(['*.md'] if resource else [])))


def safe_source(relative):
    path=ROOT/relative
    if not path.exists() or path.resolve()!=path or ROOT not in path.parents:
        raise ValueError('invalid canonical source: '+relative)
    return path


def load():
    declaration=read(ROOT/'components/composition.json')
    catalog=read(ROOT/'catalog.json')['presets']
    pairs=[(entry['platform'],entry['mode']) for entry in catalog]
    if len(set(pairs))!=len(pairs) or len({entry['id'] for entry in catalog})!=len(catalog):
        raise ValueError('catalog platform/mode and preset IDs must be unique')
    if set(declaration['presets'])!={entry['id'] for entry in catalog}:
        raise ValueError('catalog and composition declarations differ')
    aliases=declaration['aliases']
    if any(name==target or target in aliases for name,target in aliases.items()):
        raise ValueError('migration aliases must point directly to one implementation')
    return declaration,catalog


def select(declaration,entry,canonical=False):
    plan=declaration['presets'][entry['id']]
    names={};resources={};versions={};source_roots=[]
    components=list(plan['systemPacks'])
    transports=[] if canonical else plan['transports']
    for transport in transports:
        if transport['component'] not in components:components.append(transport['component'])
    if not canonical and components!=entry['generatedFrom']:
        raise ValueError('public generatedFrom differs from composition for '+entry['id'])
    for component in components:
        source=safe_source(declaration['componentRoots'][component]);source_roots.append(source)
        transport=component.startswith('transport.')
        metadata=read(source/('component.json' if transport else 'pack.json'))
        versions[component]=metadata['version']
        skill_root=source/metadata.get('skillsRoot','skills')
        requested=None
        if transport:
            requested={name for value in transports if value['component']==component for name in value['skills']}
        for skill in sorted(skill_root.iterdir()) if skill_root.exists() else []:
            if not (skill/'SKILL.md').is_file():continue
            if requested is not None and skill.name not in requested:continue
            if skill.name in declaration['aliases']:
                if skill.name in plan['compatibilityResources']:resources[skill.name]=skill
                continue
            if skill.name in names:raise ValueError('duplicate active skill '+skill.name)
            names[skill.name]=skill
        if requested is not None and not requested<=set(names):raise ValueError('missing transport skill')
    if set(resources)!=set(plan['compatibilityResources']):raise ValueError('missing legacy resources')
    if not set(declaration['aliases'].values())<=set(names):raise ValueError('migration target is absent')
    source_roots += [ROOT/'components/composition.json',ROOT/'catalog.json',ROOT/'tools/preset-install.sh',
                     ROOT/'tools/compose.py',ROOT/'tools/generate-platforms.sh']
    return names,resources,versions,source_roots,components


def populate(declaration,entry,output,canonical=False):
    names,resources,versions,roots,components=select(declaration,entry,canonical)
    skills=output/'skills';skills.mkdir(parents=True)
    for name,source in names.items():copy(source,skills/name)
    for name,source in resources.items():copy(source,skills/name,resource=True)
    migration={'schemaVersion':1,'aliases':declaration['aliases'],
               'activeSkills':sorted(names),'compatibilityResources':sorted(resources),
               'mapping':declaration['migration']}
    write(output/'migration.json',migration)
    metadata={'schemaVersion':1,'id':entry['id'],'title':entry['title'],
              'platform':entry['platform'],'mode':entry['mode'],'aliases':entry['aliases'],
              'path':'.','skillsRoot':'skills','generated':True,'generatedFrom':components,
              'componentVersions':versions,'sourceDigest':digest(roots,ROOT),
              'treeDigest':digest([skills],skills),'resources':sorted(resources),
              'skillAliases':declaration['aliases']}
    return metadata


def prepare_output(output):
    output=output.absolute()
    if output==Path('/') or output.is_symlink():raise ValueError('unsafe composition output')
    return output


def generate(output):
    declaration,catalog=load();output=prepare_output(output)
    for entry in catalog:
        preset=output/entry['platform']/entry['mode']
        if any(p.is_symlink() for p in [preset,preset.parent]):raise ValueError('output alias is unsafe')
        if preset.exists():
            marker=preset/'.generated.json'
            if not marker.is_file() or read(marker).get('id')!=entry['id']:
                raise ValueError('refusing to replace an unowned preset directory')
            shutil.rmtree(preset)
        metadata=populate(declaration,entry,preset)
        shutil.copy2(ROOT/'tools/preset-install.sh',preset/'install.sh')
        write(preset/'preset.json',metadata);write(preset/'.generated.json',metadata)
        (preset/'README.md').write_text('# Generated '+entry['platform']+' preset\n\n'
            'Generated from `components/composition.json` and canonical packs.\n'
            'Use `sh install.sh --target /path/to/skills`; review `migration.json` for legacy IDs.\n')
        (preset.parent/'README.md').write_text('# '+entry['platform']+' skills\n\n'
            '- `on-device/`: the Agent runs on the target.\n'
            '- `remote-control/`: the Agent uses the selected target Transport.\n')
    print('ok: generated '+str(len(catalog))+' declared presets')


def canonical(platform,output):
    declaration,catalog=load();output=prepare_output(output)
    entry=next(item for item in catalog if item['platform']==platform and item['mode']=='on-device')
    if output.exists():raise ValueError('canonical output must be a fresh directory')
    output.mkdir(parents=True)
    native=safe_source(declaration['componentRoots'][platform])
    for item in native.iterdir():
        if item.name=='skills':continue
        if item.is_dir():copy(item,output/item.name)
        else:shutil.copy2(item,output/item.name)
    metadata=populate(declaration,entry,output,canonical=True)
    write(output/'composition-source.json',metadata)
    print('ok: canonical '+platform+' assembled without third-party Transports')


def layer(component,output):
    declaration,_=load();output=prepare_output(output)
    if component.startswith('transport.'):raise ValueError('a Transport is not a canonical System Pack layer')
    source=safe_source(declaration['componentRoots'][component])
    if output.exists():raise ValueError('layer output must be a fresh directory')
    output.mkdir(parents=True);active=[];resources=[]
    for item in source.iterdir():
        if item.name=='skills':continue
        if item.is_dir():copy(item,output/item.name)
        else:shutil.copy2(item,output/item.name)
    (output/'skills').mkdir()
    for item in sorted((source/'skills').iterdir()) if (source/'skills').exists() else []:
        if not (item/'SKILL.md').is_file():continue
        resource=item.name in declaration['aliases']
        copy(item,output/'skills'/item.name,resource=resource)
        (resources if resource else active).append(item.name)
    write(output/'composition-source.json',{
        'schemaVersion':1,'id':component,'activeSkills':active,'compatibilityResources':resources,
        'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'sourceState':'worktree','sourceDigest':digest([source,ROOT/'components/composition.json',ROOT/'tools/compose.py'],ROOT)})
    print('ok: canonical layer '+component+'; shared skills are inherited, not duplicated')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('action',choices=['generate','canonical','layer'])
    parser.add_argument('--output',type=Path,required=True);parser.add_argument('--platform')
    args=parser.parse_args()
    try:
        if args.action=='generate':generate(args.output)
        elif args.action=='canonical':canonical(args.platform,args.output)
        else:layer(args.platform,args.output)
        return 0
    except (ValueError,OSError,KeyError,StopIteration) as error:
        print('failed: '+str(error),file=sys.stderr);return 1


if __name__=='__main__':sys.exit(main())
